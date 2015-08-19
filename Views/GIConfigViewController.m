//  Copyright (C) 2015 Pierre-Olivier Latour <info@pol-online.net>
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

#import "GIConfigViewController.h"
#import "GIWindowController.h"

#import "GIInterface.h"
#import "XLFacilityMacros.h"

@interface GIConfigViewController () <NSTableViewDataSource>
@property(nonatomic, weak) IBOutlet GITableView* tableView;
@property(nonatomic, weak) IBOutlet NSButton* editButton;
@property(nonatomic, weak) IBOutlet NSButton* deleteButton;

@property(nonatomic, strong) IBOutlet NSView* editView;
@property(nonatomic, weak) IBOutlet NSTextField* nameTextField;
@property(nonatomic, weak) IBOutlet NSTextField* valueTextField;
@end

@interface GIConfigCellView : GITableCellView
@property(nonatomic, weak) IBOutlet NSTextField* levelTextField;
@property(nonatomic, weak) IBOutlet NSTextField* optionTextField;
@property(nonatomic, weak) IBOutlet NSTextField* helpTextField;
@end

@implementation GIConfigCellView
@end

static NSMutableDictionary* _directHelp = nil;
static NSMutableDictionary* _patternHelp = nil;

@implementation GIConfigViewController {
  NSArray* _config;
  NSCountedSet* _set;
  GIConfigCellView* _cachedCellView;
  NSDictionary* _helpAttributes;
  NSDictionary* _optionAttributes;
  NSDictionary* _separatorAttributes;
  NSDictionary* _valueAttributes;
}

+ (void)initialize {
#if DEBUG
  NSMutableCharacterSet* set = [NSMutableCharacterSet alphanumericCharacterSet];
  [set addCharactersInString:@"._-"];
  [set invert];
#endif
  _directHelp = [[NSMutableDictionary alloc] init];
  _patternHelp = [[NSMutableDictionary alloc] init];
  NSString* string = [[NSString alloc] initWithContentsOfFile:[[NSBundle bundleForClass:[GIConfigViewController class]] pathForResource:@"GIConfigViewController-Help" ofType:@"txt"] encoding:NSUTF8StringEncoding error:NULL];
  XLOG_DEBUG_CHECK(string);
  string = [string stringByReplacingOccurrencesOfString:@"linkgit:" withString:@""];  // TODO: Handle links
  for (NSString* section in [string componentsSeparatedByString:@"\n\n\n"]) {
    NSRange range = [section rangeOfString:@"\n"];
    XLOG_DEBUG_CHECK(range.location != NSNotFound);
    NSString* title = [section substringToIndex:range.location];
    NSString* content = [section substringFromIndex:(range.location + range.length)];
    
    if ([title rangeOfString:@"<"].location != NSNotFound) {
      NSMutableString* pattern = [[NSMutableString alloc] initWithString:title];
      [pattern replaceOccurrencesOfString:@"." withString:@"\\." options:0 range:NSMakeRange(0, pattern.length)];
      NSRange startRange = [pattern rangeOfString:@"<" options:0 range:NSMakeRange(0, pattern.length)];
      NSRange endRange = [pattern rangeOfString:@">" options:NSBackwardsSearch range:NSMakeRange(0, pattern.length)];
      [pattern replaceCharactersInRange:NSMakeRange(startRange.location, endRange.location + endRange.length - startRange.location) withString:@".*"];
      NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
      [_patternHelp setObject:content forKey:regex];
    } else {
      XLOG_DEBUG_CHECK([title rangeOfCharacterFromSet:set].location == NSNotFound);
      XLOG_DEBUG_CHECK(![_directHelp objectForKey:[title lowercaseString]]);
      [_directHelp setObject:content forKey:[title lowercaseString]];
    }
  }
}

+ (NSString*)helpForVariable:(NSString*)variable {
  NSString* help = [_directHelp objectForKey:variable];
  if (help) {
    return help;
  }
  for (NSRegularExpression* expression in _patternHelp) {
    if ([expression rangeOfFirstMatchInString:variable options:0 range:NSMakeRange(0, variable.length)].location != NSNotFound) {
      return _patternHelp[expression];
    }
  }
  return NSLocalizedString(@"No help available for this variable.", nil);
}

- (void)loadView {
  [super loadView];
  
  _tableView.target = self;
  _tableView.doubleAction = @selector(editOption:);
  
  _cachedCellView = [_tableView makeViewWithIdentifier:[_tableView.tableColumns[0] identifier] owner:self];
  
  NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
  style.paragraphSpacing = -6;
  _helpAttributes = @{NSParagraphStyleAttributeName: style};
  
  CGFloat fontSize = _cachedCellView.optionTextField.font.pointSize;
  _optionAttributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize]};
  _separatorAttributes = @{NSFontAttributeName: [NSFont systemFontOfSize:fontSize]};
  _valueAttributes = @{NSFontAttributeName: [NSFont systemFontOfSize:fontSize], NSBackgroundColorAttributeName: [NSColor colorWithDeviceRed:1.0 green:1.0 blue:0.0 alpha:0.5]};
}

- (void)viewWillShow {
  [self _reloadConfig];
}

- (void)viewDidResize {
  if (self.viewVisible && !self.liveResizing) {
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.0];  // Prevent animations in case the view is actually not on screen yet (e.g. in a hidden tab)
    [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _config.count)]];
    [NSAnimationContext endGrouping];
  }
}

- (void)repositoryDidChange {
  if (self.viewVisible) {
    [self _reloadConfig];
  }
}

- (void)viewDidHide {
  _config = nil;
  _set = nil;
  [_tableView reloadData];
}

- (void)viewDidFinishLiveResize {
  [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _config.count)]];
}

- (BOOL)_selectOptionWithLevel:(GCConfigLevel)level variable:(NSString*)variable {
  NSUInteger row = 0;
  for (GCConfigOption* option in _config) {
    if ((option.level == level) && [option.variable isEqualToString:variable]) {
      [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
      [_tableView scrollRowToVisible:row];
      return YES;
    }
    ++row;
  }
  return NO;
}

- (void)_reloadConfig {
  NSInteger selectedRow = _tableView.selectedRow;
  GCConfigOption* selectedOption = (selectedRow >= 0 ? _config[selectedRow] : nil);
  
  NSError* error;
  NSArray* config = [self.repository readAllConfigs:&error];
  if (config) {
    _config = [config sortedArrayUsingComparator:^NSComparisonResult(GCConfigOption* option1, GCConfigOption* option2) {
      NSComparisonResult result = [option1.variable compare:option2.variable];
      if (result == NSOrderedSame) {
        if (option1.level < option2.level) {
          result = NSOrderedAscending;
        } else if (option1.level > option2.level) {
          result = NSOrderedDescending;
        } else {
          XLOG_DEBUG_UNREACHABLE();
        }
      }
      return result;
    }];
    _set = [[NSCountedSet alloc] init];
    for (GCConfigOption* option in _config) {
      [_set addObject:option.variable];
    }
  } else {
    _config = nil;
    _set = nil;
    [self presentError:error];
  }
  [_tableView reloadData];
  XLOG_VERBOSE(@"Reloaded config for \"%@\"", self.repository.repositoryPath);
  
  if (selectedOption && ![self _selectOptionWithLevel:selectedOption.level variable:selectedOption.variable]) {
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
  }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return _config.count;
}

#pragma mark - NSTableViewDelegate

- (void)tableView:(NSTableView*)tableView didAddRowView:(NSTableRowView*)rowView forRow:(NSInteger)row {
  GCConfigOption* option = _config[row];
  if ([_set countForObject:option.variable] > 1) {
    rowView.backgroundColor = [NSColor colorWithDeviceRed:1.0 green:0.95 blue:0.95 alpha:1.0];
  } else if (option.level != kGCConfigLevel_Local) {
    rowView.backgroundColor = [NSColor colorWithDeviceRed:0.95 green:1.0 blue:0.95 alpha:1.0];
  } else {
    rowView.backgroundColor = [NSColor whiteColor];
  }
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
  GIConfigCellView* view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
  view.row = row;
  GCConfigOption* option = _config[row];
  switch (option.level) {
    
    case kGCConfigLevel_System:
      view.levelTextField.stringValue = NSLocalizedString(@"System", nil);
      break;
    
    case kGCConfigLevel_XDG:
      view.levelTextField.stringValue = NSLocalizedString(@"XDG", nil);
      break;
    
    case kGCConfigLevel_Global:
      view.levelTextField.stringValue = NSLocalizedString(@"Global", nil);
      break;
    
    case kGCConfigLevel_Local:
      view.levelTextField.stringValue = NSLocalizedString(@"Local", nil);
      break;
    
  }
  NSMutableAttributedString* string = [[NSMutableAttributedString alloc] init];
  [string appendString:option.variable withAttributes:_optionAttributes];
  [string appendString:@" = " withAttributes:_separatorAttributes];
  [string appendString:option.value withAttributes:_valueAttributes];
  view.optionTextField.attributedStringValue = string;
  view.helpTextField.attributedStringValue = [[NSAttributedString alloc] initWithString:[self.class helpForVariable:option.variable] attributes:_helpAttributes];
  return view;
}

- (CGFloat)tableView:(NSTableView*)tableView heightOfRow:(NSInteger)row {
  GCConfigOption* option = _config[row];
  _cachedCellView.frame = NSMakeRect(0, 0, [_tableView.tableColumns[0] width], 1000);
  NSTextField* textField = _cachedCellView.helpTextField;
  NSRect frame = textField.frame;
  textField.attributedStringValue = [[NSAttributedString alloc] initWithString:[self.class helpForVariable:option.variable] attributes:_helpAttributes];
  NSSize size = [textField.cell cellSizeForBounds:NSMakeRect(0, 0, frame.size.width, HUGE_VALF)];
  CGFloat delta = ceilf(size.height) - frame.size.height;
  return _cachedCellView.frame.size.height + delta;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  NSInteger row = _tableView.selectedRow;
  _editButton.enabled = (row >= 0);
  _deleteButton.enabled = (row >= 0);
}

#pragma mark - Actions

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  
  if (item.action == @selector(copy:)) {
    return (_tableView.selectedRow >= 0);
  }
  
  return NO;
}

- (IBAction)copy:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    GCConfigOption* option = _config[row];
    [[NSPasteboard generalPasteboard] declareTypes:@[NSPasteboardTypeString] owner:nil];
    [[NSPasteboard generalPasteboard] setString:[NSString stringWithFormat:@"%@ = %@", option.variable, option.value] forType:NSPasteboardTypeString];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (void)_undoWriteOptionWithLevel:(GCConfigLevel)level variable:(NSString*)variable value:(NSString*)value ignore:(BOOL)ignore {
  if (ignore) {
    [[self.undoManager prepareWithInvocationTarget:self] _undoWriteOptionWithLevel:level variable:variable value:value ignore:NO];
    return;
  }
  
  NSError* error;
  GCConfigOption* currentOption = [self.repository readConfigOptionForLevel:level variable:variable error:&error];
  if ((currentOption || ([error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_NotFound)))
    && [self.repository writeConfigOptionForLevel:level variable:variable withValue:value error:&error]) {
    [[self.undoManager prepareWithInvocationTarget:self] _undoWriteOptionWithLevel:level variable:variable value:currentOption.value ignore:NO];
    [self.repository notifyRepositoryChanged];
  } else {  // In case of error, put a dummy operation on the undo stack since we *must* put something, but pop it at the next runloop iteration
    [[self.undoManager prepareWithInvocationTarget:self] _undoWriteOptionWithLevel:level variable:variable value:value ignore:YES];
    [self.undoManager performSelector:(self.undoManager.isRedoing ? @selector(undo) : @selector(redo)) withObject:nil afterDelay:0.0];
    [self presentError:error];
  }
}

- (void)_promptOption:(GCConfigOption*)option {
  _nameTextField.stringValue = option ? option.variable : @"";
  _valueTextField.stringValue = option ? option.value : @"";
  _nameTextField.editable = (option == nil);
  _nameTextField.textColor = option ? [NSColor grayColor] : _valueTextField.textColor;
  [self.windowController runModalView:_editView withInitialFirstResponder:(option ? _valueTextField : _nameTextField) completionHandler:^(BOOL success) {
    
    if (success) {
      NSString* name = option ? option.variable : [_nameTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      NSString* value = [_valueTextField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (name.length && value.length) {
        NSError* error;
        GCConfigOption* currentOption = option ? option : [self.repository readConfigOptionForLevel:kGCConfigLevel_Local variable:name error:&error];
        if ((currentOption || ([error.domain isEqualToString:GCErrorDomain] && (error.code == kGCErrorCode_NotFound)))
          && [self.repository writeConfigOptionForLevel:(option ? option.level : kGCConfigLevel_Local) variable:name withValue:value error:&error]) {
          [self.undoManager setActionName:NSLocalizedString(@"Edit Configuration", nil)];
          [[self.undoManager prepareWithInvocationTarget:self] _undoWriteOptionWithLevel:(option ? option.level : kGCConfigLevel_Local) variable:name value:currentOption.value ignore:NO];  // TODO: We should really use the built-in undo mechanism from GCLiveRepository
          [self.repository notifyRepositoryChanged];
          
          if (!option) {
            [self _selectOptionWithLevel:kGCConfigLevel_Local variable:name];
          }
        } else {
          [self presentError:error];
        }
      } else {
        NSBeep();
      }
    }
    
  }];
}

- (IBAction)addOption:(id)sender {
  [self _promptOption:nil];
}

- (IBAction)editOption:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    [self _promptOption:_config[row]];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

- (IBAction)deleteOption:(id)sender {
  NSInteger row = _tableView.selectedRow;
  if (row >= 0) {
    GCConfigOption* option = _config[row];
    NSError* error;
    if ([self.repository writeConfigOptionForLevel:option.level variable:option.variable withValue:nil error:&error]) {
      [self.undoManager setActionName:NSLocalizedString(@"Edit Configuration", nil)];
      [[self.undoManager prepareWithInvocationTarget:self] _undoWriteOptionWithLevel:option.level variable:option.variable value:option.value ignore:NO];  // TODO: We should really use the built-in undo mechanism from GCLiveRepository
      [self.repository notifyRepositoryChanged];
    } else {
      [self presentError:error];
    }
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

@end
