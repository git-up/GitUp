//  Copyright (C) 2015-2019 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#if !__has_feature(objc_arc)
#error This file requires ARC
#endif

#import "GCPrivate.h"

#if !TARGET_OS_IPHONE

static NSString* _StringFromTaskOutput(NSData* data) {
  return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL _ReadConfigBool(GCRepository* repository, const char* variable, BOOL* value, NSError** error) {
  BOOL success = NO;
  git_config* config = NULL;
  int boolValue = 0;
  int status;

  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_config, &config, repository.private);
  status = git_config_get_bool(&boolValue, config, variable);
  if (status == GIT_ENOTFOUND) {
    *value = NO;
    success = YES;
    goto cleanup;
  }
  CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
  *value = boolValue ? YES : NO;
  success = YES;

cleanup:
  git_config_free(config);
  return success;
}

static BOOL _ShouldSSHSignCommit(GCRepository* repository, BOOL* shouldSign, NSError** error) {
  BOOL gpgSign = NO;
  if (!_ReadConfigBool(repository, "commit.gpgsign", &gpgSign, error)) {
    return NO;
  }
  if (!gpgSign) {
    *shouldSign = NO;
    return YES;
  }

  NSString* format = [[repository readConfigOptionForVariable:@"gpg.format" error:NULL] value];
  if (!format.length || ([format caseInsensitiveCompare:@"ssh"] != NSOrderedSame)) {
    // v1 intentionally supports SSH commit signing only. Preserve existing GitUp behavior for OpenPGP/X.509 configs by creating an unsigned commit.
    *shouldSign = NO;
    return YES;
  }

  *shouldSign = YES;
  return YES;
}

static NSString* _CommitSigningPATH(GCRepository* repository, NSError** error) {
  static NSString* cachedPATH = nil;
  if (cachedPATH == nil) {
    cachedPATH = [repository getPATHUsingShell:NSProcessInfo.processInfo.environment[@"SHELL"] error:error] ?: [repository getPATHUsingShell:@"/bin/sh" error:error];
    XLOG_DEBUG_CHECK(cachedPATH);
  }
  return cachedPATH;
}

static BOOL _LooksLikeInlineSSHKey(NSString* key) {
  return [key hasPrefix:@"ssh-"] || [key hasPrefix:@"ecdsa-"] || [key hasPrefix:@"sk-"];
}

static NSString* _SSHKeyFromDefaultKeyCommand(GCRepository* repository, NSString* command, NSError** error) {
  NSString* path = _CommitSigningPATH(repository, error);
  if (!path) {
    return nil;
  }

  GCTask* task = [[GCTask alloc] initWithExecutablePath:@"/bin/sh"];
  task.currentDirectoryPath = repository.workingDirectoryPath ?: repository.repositoryPath;
  task.additionalEnvironment = @{@"PATH" : path};
  int status;
  NSData* stdoutData;
  NSData* stderrData;
  if (![task runWithArguments:@[ @"-c", command ] stdin:nil stdout:&stdoutData stderr:&stderrData exitStatus:&status error:error]) {
    return nil;
  }
  if (status != 0) {
    if (error) {
      NSString* output = _StringFromTaskOutput(stderrData.length ? stderrData : stdoutData);
      *error = GCNewError(kGCErrorCode_Generic, [NSString stringWithFormat:@"SSH signing default key command exited with non-zero status (%i)%@", status, output.length ? [NSString stringWithFormat:@": %@", output] : @""]);
    }
    return nil;
  }

  NSString* output = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
  for (NSString* line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
    NSString* trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmedLine hasPrefix:@"key::"]) {
      NSString* key = [trimmedLine substringFromIndex:5];
      return key.length ? key : nil;
    }
  }
  if (error) {
    *error = GCNewError(kGCErrorCode_Generic, @"SSH signing default key command did not return a key:: entry");
  }
  return nil;
}

static NSString* _TemporaryKeyFileForInlineSSHKey(NSString* key, NSError** error) {
  NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString* contents = [key hasSuffix:@"\n"] ? key : [key stringByAppendingString:@"\n"];
  if (![contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]) {
    return nil;
  }
  return path;
}

static NSString* _SSHSigningKeyPath(GCRepository* repository, NSString** temporaryPath, NSError** error) {
  NSString* key = [[repository readConfigOptionForVariable:@"user.signingkey" error:NULL] value];
  if (key.length) {
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  } else {
    NSString* command = [[repository readConfigOptionForVariable:@"gpg.ssh.defaultKeyCommand" error:NULL] value];
    if (!command.length) {
      if (error) {
        *error = GCNewError(kGCErrorCode_Generic, @"SSH commit signing requires user.signingkey or gpg.ssh.defaultKeyCommand");
      }
      return nil;
    }
    key = _SSHKeyFromDefaultKeyCommand(repository, command, error);
    if (!key) {
      return nil;
    }
  }

  if ([key hasPrefix:@"key::"]) {
    key = [key substringFromIndex:5];
  }
  if (_LooksLikeInlineSSHKey(key)) {
    NSString* path = _TemporaryKeyFileForInlineSSHKey(key, error);
    if (!path) {
      return nil;
    }
    *temporaryPath = path;
    return path;
  }

  NSString* path = key.stringByExpandingTildeInPath;
  if (!path.absolutePath) {
    NSString* workingDirectoryPath = repository.workingDirectoryPath ?: repository.repositoryPath;
    NSString* relativePath = [workingDirectoryPath stringByAppendingPathComponent:path];
    if ([[NSFileManager defaultManager] fileExistsAtPath:relativePath]) {
      path = relativePath;
    }
  }
  return path;
}

static NSString* _SSHSignatureForCommitBuffer(GCRepository* repository, NSData* commitBuffer, NSError** error) {
  NSString* temporaryKeyPath = nil;
  NSString* keyPath = _SSHSigningKeyPath(repository, &temporaryKeyPath, error);
  if (!keyPath) {
    return nil;
  }

  NSString* path = _CommitSigningPATH(repository, error);
  if (!path) {
    if (temporaryKeyPath) {
      [[NSFileManager defaultManager] removeItemAtPath:temporaryKeyPath error:NULL];
    }
    return nil;
  }

  NSString* program = [[repository readConfigOptionForVariable:@"gpg.ssh.program" error:NULL] value];
  program = program.length ? program.stringByExpandingTildeInPath : @"ssh-keygen";

  GCTask* task = [[GCTask alloc] initWithExecutablePath:@"/usr/bin/env"];
  task.currentDirectoryPath = repository.workingDirectoryPath ?: repository.repositoryPath;
  task.additionalEnvironment = @{@"PATH" : path};
  int status;
  NSData* stdoutData;
  NSData* stderrData;
  NSArray* arguments = @[ program, @"-Y", @"sign", @"-n", @"git", @"-f", keyPath ];
  BOOL success = [task runWithArguments:arguments stdin:commitBuffer stdout:&stdoutData stderr:&stderrData exitStatus:&status error:error];
  if (temporaryKeyPath) {
    [[NSFileManager defaultManager] removeItemAtPath:temporaryKeyPath error:NULL];
  }
  if (!success) {
    return nil;
  }
  if (status != 0) {
    if (error) {
      NSString* output = _StringFromTaskOutput(stderrData.length ? stderrData : stdoutData);
      *error = GCNewError(kGCErrorCode_Generic, [NSString stringWithFormat:@"SSH commit signer exited with non-zero status (%i)%@", status, output.length ? [NSString stringWithFormat:@": %@", output] : @""]);
    }
    return nil;
  }

  NSString* signature = _StringFromTaskOutput(stdoutData);
  if (!signature.length) {
    if (error) {
      *error = GCNewError(kGCErrorCode_Generic, @"SSH commit signer did not return a signature");
    }
    return nil;
  }
  return signature;
}

#endif

static GCCommit* _CreateCommitFromTree(GCRepository* repository, git_tree* tree, const git_commit** parents, NSUInteger count, const git_signature* author, NSString* message, NSError** error) {
  GCCommit* commit = nil;
  git_signature* signature = NULL;
  git_commit* newCommit = NULL;
  NSData* cleanedMessage = nil;
#if !TARGET_OS_IPHONE
  git_buf commitBuffer = {0};
  NSData* commitData = nil;
  NSString* sshSignature = nil;
  BOOL shouldSign = NO;
#endif

  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_signature_default, &signature, repository.private);
  cleanedMessage = GCCleanedUpCommitMessage(message);
#if !TARGET_OS_IPHONE
  if (!_ShouldSSHSignCommit(repository, &shouldSign, error)) {
    goto cleanup;
  }

  if (shouldSign) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_create_buffer, &commitBuffer, repository.private, author ? author : signature, signature, NULL, cleanedMessage.bytes, tree, count, parents);
    commitData = [[NSData alloc] initWithBytes:commitBuffer.ptr length:commitBuffer.size];
    sshSignature = _SSHSignatureForCommitBuffer(repository, commitData, error);
    if (!sshSignature) {
      goto cleanup;
    }
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_create_with_signature, &oid, repository.private, commitBuffer.ptr, sshSignature.UTF8String, "gpgsig");
  } else {
#endif
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_create, &oid, repository.private, NULL, author ? author : signature, signature, NULL, cleanedMessage.bytes, tree, count, parents);
#if !TARGET_OS_IPHONE
  }
#endif
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &newCommit, repository.private, &oid);
  commit = [[GCCommit alloc] initWithRepository:repository commit:newCommit];
  newCommit = NULL;

cleanup:
  git_commit_free(newCommit);
#if !TARGET_OS_IPHONE
  git_buf_free(&commitBuffer);
#endif
  git_signature_free(signature);
  return commit;
}

static GCCommit* _CreateCommitFromIndex(GCRepository* repository, git_index* index, const git_commit** parents, NSUInteger count, const git_signature* author, NSString* message, NSError** error) {
  GCCommit* commit = nil;
  git_tree* tree = NULL;

  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_write_tree_to, &oid, index, repository.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_tree_lookup, &tree, repository.private, &oid);
  commit = _CreateCommitFromTree(repository, tree, parents, count, author, message, error);

cleanup:
  git_tree_free(tree);
  return commit;
}

@implementation GCRepository (HEAD)

#pragma mark - HEAD Manipulation

- (BOOL)isHEADUnborn {
  int status = git_repository_head_unborn(self.private);
  if (status > 0) {
    return YES;
  }
  if (status < 0) {
    XLOG_DEBUG_UNREACHABLE();
    LOG_LIBGIT2_ERROR(status);
  }
  return NO;
}

- (GCReference*)lookupHEADReference:(NSError**)error {
  git_reference* reference;
  CALL_LIBGIT2_FUNCTION_RETURN(nil, git_reference_lookup, &reference, self.private, kHEADReferenceFullName);
  return [[GCReference alloc] initWithRepository:self reference:reference];
}

- (GCCommit*)lookupHEAD:(GCLocalBranch**)currentBranch error:(NSError**)error {
  git_reference* headReference = NULL;
  git_commit* headCommit = [self loadHEADCommit:(currentBranch ? &headReference : NULL) error:error];
  if (headCommit == NULL) {
    return NULL;
  }
  if (currentBranch) {
    *currentBranch = headReference ? [[GCLocalBranch alloc] initWithRepository:self reference:headReference] : nil;
  }
  return [[GCCommit alloc] initWithRepository:self commit:headCommit];
}

- (BOOL)lookupHEADCurrentCommit:(GCCommit**)commit branch:(GCLocalBranch**)branch error:(NSError**)error {
  git_commit* headCommit = NULL;
  git_reference* headReference = NULL;
  if (![self loadHEADCommit:(commit ? &headCommit : NULL) resolvedReference:(branch ? &headReference : NULL)error:error]) {
    return NO;
  }
  if (commit) {
    *commit = headCommit ? [[GCCommit alloc] initWithRepository:self commit:headCommit] : nil;
  }
  if (branch) {
    *branch = headReference ? [[GCLocalBranch alloc] initWithRepository:self reference:headReference] : nil;
  }
  return YES;
}

- (BOOL)setHEADToReference:(GCReference*)reference error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_repository_set_head, self.private, git_reference_name(reference.private));  // This uses a "checkout: " reflog message
  return YES;
}

- (BOOL)setDetachedHEADToCommit:(GCCommit*)commit error:(NSError**)error {
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_repository_set_head_detached, self.private, git_commit_id(commit.private));  // This uses a "checkout: " reflog message
  return YES;
}

- (BOOL)moveHEADToCommit:(GCCommit*)commit reflogMessage:(NSString*)message error:(NSError**)error {
  git_reference* headReference;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_repository_head, &headReference, self.private);
  BOOL success = [self setTargetOID:git_commit_id(commit.private) forReference:headReference reflogMessage:message newReference:NULL error:error];
  git_reference_free(headReference);
  return success;
}

#pragma mark - Commit Creation

- (GCCommit*)createCommitFromHEADWithMessage:(NSString*)message error:(NSError**)error {
  return [self createCommitFromHEADAndOtherParent:nil withMessage:message error:error];
}

- (GCCommit*)createCommitFromHEADAndOtherParent:(GCCommit*)parent withMessage:(NSString*)message error:(NSError**)error {
  BOOL success = NO;
  GCCommit* commit = nil;
  git_reference* headReference = NULL;
  git_commit* headCommit = NULL;
  git_index* index = NULL;
  NSString* reflogMessage;

  int status = git_repository_head(&headReference, self.private);  // Returns a direct reference or GIT_EUNBORNBRANCH
  if (status != GIT_EUNBORNBRANCH) {
    CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
    XLOG_DEBUG_CHECK(git_reference_type(headReference) == GIT_REF_OID);
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &headCommit, self.private, git_reference_target(headReference));
  } else if (parent) {
    GC_SET_GENERIC_ERROR(@"Secondary parent not allowed for unborn HEAD");
    goto cleanup;
  }

  index = [self reloadRepositoryIndex:error];
  if (index == NULL) {
    goto cleanup;
  }

  const git_commit* parents[2] = {headCommit, parent.private};
  commit = _CreateCommitFromIndex(self, index, parents, (headCommit ? (parent ? 2 : 1) : 0), NULL, message, error);
  if (commit == nil) {
    goto cleanup;
  }

  if (headReference == NULL) {
    CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_lookup, &headReference, self.private, kHEADReferenceFullName);
  }
  if (headCommit) {
    reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_Git_Commit, commit.summary];
  } else {
    reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_Git_Commit_Initial, commit.summary];
  }
  if (![self setTargetOID:git_commit_id(commit.private) forReference:headReference reflogMessage:reflogMessage newReference:NULL error:error]) {
    goto cleanup;
  }

  if (![self cleanupState:error]) {
    goto cleanup;
  }
  success = YES;

cleanup:
  git_index_free(index);
  git_commit_free(headCommit);
  git_reference_free(headReference);
  return success ? commit : nil;
}

- (GCCommit*)createCommitByAmendingHEADWithMessage:(NSString*)message error:(NSError**)error {
  BOOL success = NO;
  GCCommit* commit = nil;
  git_reference* headReference = NULL;
  git_commit* headCommit = NULL;
  git_index* index = NULL;
  git_tree* tree = NULL;
  git_commit** parentCommits = NULL;
  NSString* reflogMessage;

  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_repository_head, &headReference, self.private);  // Returns a direct reference or GIT_EUNBORNBRANCH
  XLOG_DEBUG_CHECK(git_reference_type(headReference) == GIT_REF_OID);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_lookup, &headCommit, self.private, git_reference_target(headReference));

  index = [self reloadRepositoryIndex:error];
  if (index == NULL) {
    goto cleanup;
  }

  git_oid oid;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_index_write_tree_to, &oid, index, self.private);
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_tree_lookup, &tree, self.private, &oid);
  unsigned int parentCount = git_commit_parentcount(headCommit);
  if (parentCount) {
    parentCommits = calloc(parentCount, sizeof(git_commit*));
    if (!parentCommits) {
      GC_SET_GENERIC_ERROR(@"Unable to allocate commit parent list");
      goto cleanup;
    }
    for (unsigned int i = 0; i < parentCount; ++i) {
      CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_commit_parent, &parentCommits[i], headCommit, i);
    }
  }
  commit = _CreateCommitFromTree(self, tree, (const git_commit**)parentCommits, parentCount, git_commit_author(headCommit), message, error);
  if (commit == nil) {
    goto cleanup;
  }

  reflogMessage = [NSString stringWithFormat:kGCReflogMessageFormat_Git_Commit_Amend, commit.summary];
  if (![self setTargetOID:git_commit_id(commit.private) forReference:headReference reflogMessage:reflogMessage newReference:NULL error:error]) {
    goto cleanup;
  }

  if (![self cleanupState:error]) {
    goto cleanup;
  }
  success = YES;

cleanup:
  if (parentCommits) {
    for (unsigned int i = 0, count = headCommit ? git_commit_parentcount(headCommit) : 0; i < count; ++i) {
      git_commit_free(parentCommits[i]);
    }
    free(parentCommits);
  }
  git_tree_free(tree);
  git_index_free(index);
  git_commit_free(headCommit);
  git_reference_free(headReference);
  return success ? commit : nil;
}

#pragma mark - Checkout

- (BOOL)_checkoutTreeForCommit:(GCCommit*)commit
                  withBaseline:(GCCommit*)baseline
                       options:(GCCheckoutOptions)options
                         error:(NSError**)error {
  CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
  git_tree* tree = NULL;
  git_checkout_options checkoutOptions = GIT_CHECKOUT_OPTIONS_INIT;
  checkoutOptions.checkout_strategy = options & kGCCheckoutOption_Force ? GIT_CHECKOUT_FORCE : GIT_CHECKOUT_SAFE;

  if (options & kGCCheckoutOption_RemoveUntrackedFiles) {
    checkoutOptions.checkout_strategy |= GIT_CHECKOUT_REMOVE_UNTRACKED;
  }

  if (baseline) {
    CALL_LIBGIT2_FUNCTION_RETURN(NO, git_commit_tree, &tree, baseline.private);
    checkoutOptions.baseline = tree;
  }
  int status = git_checkout_tree(self.private, (git_object*)commit.private, &checkoutOptions);
  git_tree_free(tree);
  CHECK_LIBGIT2_FUNCTION_CALL(return NO, status, == GIT_OK);
  XLOG_VERBOSE(@"Checked out %@ from \"%@\" in %.3f seconds", commit ? commit.shortSHA1 : @"HEAD", self.repositoryPath, CFAbsoluteTimeGetCurrent() - time);
  return YES;
}

// Because by default git_checkout_tree() assumes the baseline (i.e. expected content of workdir) is HEAD we must checkout first, then update HEAD
- (BOOL)checkoutCommit:(GCCommit*)commit options:(GCCheckoutOptions)options error:(NSError**)error {
  if (![self _checkoutTreeForCommit:commit withBaseline:nil options:options error:error] || ![self setDetachedHEADToCommit:commit error:error]) {
    return NO;
  }
  if (options & kGCCheckoutOption_UpdateSubmodulesRecursively) {
    return [self updateAllSubmodulesResursively:(options & kGCCheckoutOption_Force ? YES : NO) error:error];  // This must happen after moving HEAD
  }
  return YES;
}

- (BOOL)updateSubmoduleReferenceAtPath:(NSString*)submodulePath toCommitSHA1:(NSString*)commitSHA1 error:(NSError**)error {
  GCSubmodule* submodule = [self lookupSubmoduleWithName:submodulePath error:error];
  if (!submodule) {
    return NO;
  }

  GCRepository* submoduleRepository = [[GCRepository alloc] initWithSubmodule:submodule error:error];
  if (!submoduleRepository) {
    return NO;
  }

  GCCommit* targetCommit = [submoduleRepository findCommitWithSHA1:commitSHA1 error:error];
  if (!targetCommit) {
    return NO;
  }

  return [submoduleRepository checkoutCommit:targetCommit options:kGCCheckoutOption_UpdateSubmodulesRecursively error:error];
}

// Because by default git_checkout_tree() assumes the baseline (i.e. expected content of workdir) is HEAD we must checkout first, then update HEAD
- (BOOL)checkoutLocalBranch:(GCLocalBranch*)branch options:(GCCheckoutOptions)options error:(NSError**)error {
  GCCommit* tipCommit = [self lookupTipCommitForBranch:branch error:error];
  if (!tipCommit || ![self _checkoutTreeForCommit:tipCommit withBaseline:nil options:options error:error] || ![self setHEADToReference:branch error:error]) {
    return NO;
  }
  if (options & kGCCheckoutOption_UpdateSubmodulesRecursively) {
    return [self updateAllSubmodulesResursively:(options & kGCCheckoutOption_Force ? YES : NO) error:error];  // This must happen after moving HEAD
  }
  return YES;
}

- (BOOL)checkoutTreeForCommit:(GCCommit*)commit
                 withBaseline:(GCCommit*)baseline
                      options:(GCCheckoutOptions)options
                        error:(NSError**)error {
  if (![self _checkoutTreeForCommit:commit withBaseline:baseline options:options error:error]) {
    return NO;
  }
  if (options & kGCCheckoutOption_UpdateSubmodulesRecursively) {
    return [self updateAllSubmodulesResursively:(options & kGCCheckoutOption_Force ? YES : NO) error:error];
  }
  return YES;
}

- (BOOL)checkoutIndex:(GCIndex*)index withOptions:(GCCheckoutOptions)options error:(NSError**)error {
  git_checkout_options checkoutOptions = GIT_CHECKOUT_OPTIONS_INIT;
  checkoutOptions.checkout_strategy = options & kGCCheckoutOption_Force ? GIT_CHECKOUT_FORCE : GIT_CHECKOUT_SAFE;
  checkoutOptions.checkout_strategy |= GIT_CHECKOUT_ALLOW_CONFLICTS;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_checkout_index, self.private, index.private, &checkoutOptions);
  if (options & kGCCheckoutOption_UpdateSubmodulesRecursively) {
    return [self updateAllSubmodulesResursively:(options & kGCCheckoutOption_Force ? YES : NO) error:error];
  }
  return YES;
}

- (BOOL)checkoutFileToWorkingDirectory:(NSString*)path fromCommit:(GCCommit*)commit skipIndex:(BOOL)skipIndex error:(NSError**)error {
  git_checkout_options options = GIT_CHECKOUT_OPTIONS_INIT;
  options.checkout_strategy = GIT_CHECKOUT_FORCE | GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH;
  if (skipIndex) {
    options.checkout_strategy |= GIT_CHECKOUT_DONT_UPDATE_INDEX;
  }
  options.paths.count = 1;
  const char* filePath = GCGitPathFromFileSystemPath(path);
  options.paths.strings = (char**)&filePath;
  CALL_LIBGIT2_FUNCTION_RETURN(NO, git_checkout_tree, self.private, (git_object*)commit.private, &options);
  return YES;
}

@end

@implementation GCRepository (HEAD_Private)

- (git_commit*)loadHEADCommit:(git_reference**)resolvedReference error:(NSError**)error {
  git_commit* commit;
  if (![self loadHEADCommit:&commit resolvedReference:resolvedReference error:error]) {
    return NULL;
  }
  if (commit == NULL) {
    GC_SET_GENERIC_ERROR(@"HEAD is unborn");
    return NULL;
  }
  return commit;
}

- (BOOL)loadHEADCommit:(git_commit**)commit resolvedReference:(git_reference**)resolvedReference error:(NSError**)error {
  BOOL success = NO;
  git_reference* headReference = NULL;

  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_reference_lookup, &headReference, self.private, kHEADReferenceFullName);
  // Check if HEAD is attached or unborn
  if (git_reference_type(headReference) == GIT_REF_SYMBOLIC) {
    git_reference* branchReference;
    int status = git_reference_resolve(&branchReference, headReference);
    // Check if HEAD is unborn
    if (status == GIT_ENOTFOUND) {
      if (commit) {
        *commit = NULL;
      }
      if (resolvedReference) {
        *resolvedReference = NULL;
      }
    }
    // Otherwise HEAD is attached
    else {
      CHECK_LIBGIT2_FUNCTION_CALL(goto cleanup, status, == GIT_OK);
      if (commit) {
        *commit = [self loadCommitFromBranchReference:branchReference error:error];
        if (*commit == NULL) {
          goto cleanup;
        }
      }
      if (resolvedReference) {
        *resolvedReference = branchReference;
      } else {
        git_reference_free(branchReference);
      }
    }
  }
  // Otherwise HEAD is detached
  else {
    XLOG_DEBUG_CHECK(git_reference_type(headReference) == GIT_REF_OID);
    if (commit) {
      *commit = [self loadCommitFromBranchReference:headReference error:error];
      if (*commit == NULL) {
        goto cleanup;
      }
    }
    if (resolvedReference) {
      *resolvedReference = NULL;
    }
  }
  success = YES;

cleanup:
  git_reference_free(headReference);
  return success;
}

#if DEBUG

- (BOOL)mergeCommitToHEAD:(GCCommit*)commit error:(NSError**)error {
  BOOL success = NO;
  git_annotated_commit* annotatedCommit = NULL;

  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_annotated_commit_lookup, &annotatedCommit, self.private, git_commit_id(commit.private));
  git_merge_options mergeOptions = GIT_MERGE_OPTIONS_INIT;
  git_checkout_options checkoutOptions = GIT_CHECKOUT_OPTIONS_INIT;
  checkoutOptions.checkout_strategy = GIT_CHECKOUT_SAFE;
  CALL_LIBGIT2_FUNCTION_GOTO(cleanup, git_merge, self.private, (const git_annotated_commit**)&annotatedCommit, 1, &mergeOptions, &checkoutOptions);
  success = YES;

cleanup:
  git_annotated_commit_free(annotatedCommit);
  return success;
}

#endif

@end
