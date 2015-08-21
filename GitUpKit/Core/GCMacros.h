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

#import <stdlib.h>

#pragma mark - GCItemList

typedef struct {
  void* items;
  size_t size;
  size_t capacity;
  size_t count;
} GCItemList;

static inline void __GCItemListInitialize(GCItemList* list, size_t initialCapacity, size_t itemSize) {
  list->count = 0;
  list->capacity = initialCapacity;
#ifdef __clang_analyzer__
  list->capacity += 1;  // Prevent clang from complaining about calling malloc() with a size of 0
#endif
  list->items = malloc(list->capacity * itemSize);
  list->size = itemSize;
}

#define GC_LIST_INITIALIZE(name, initialCapacity, itemType) __GCItemListInitialize(&name, initialCapacity, sizeof(itemType))

#define GC_LIST_ALLOCATE(name, initialCapacity, itemType) \
  __block GCItemList name; \
  GC_LIST_INITIALIZE(name, initialCapacity, itemType)

#define GC_LIST_ROOT_POINTER(name) name.items

#define GC_LIST_COUNT(name) name.count

#define GC_LIST_CAPACITY(name) name.capacity

#define GC_LIST_ITEM_POINTER(name, index) (name.items + (index) * name.size)

static inline void __GCItemListAppend(GCItemList* list, const void* itemPointer) {
  if (list->count == list->capacity) {
    list->capacity *= 2;
#ifdef __clang_analyzer__
    list->capacity += 1;  // Prevent clang from complaining about calling realloc() with a size of 0
#endif
    list->items = realloc(list->items, list->capacity * list->size);
  }
  if (list->size == sizeof(unsigned long)) {  // Fast path for 32 and 64 bit architectures
    *(unsigned long*)(list->items + list->count * list->size) = *(unsigned long*)itemPointer;
  } else {
    bcopy(itemPointer, list->items + list->count * list->size, list->size);
  }
  list->count += 1;
}

#define GC_LIST_APPEND(name, itemPointer) __GCItemListAppend(&name, itemPointer)

#define GC_LIST_FOR_LOOP_POINTER(name, pointer) \
  pointer = (typeof(pointer))name.items; \
  for (size_t __##name = 0; (__##name < name.count) && (pointer = (typeof(pointer))GC_LIST_ITEM_POINTER(name, __##name), 1); ++__##name)

#define GC_LIST_TRUNCATE(name, newCount) name.count = newCount

#define GC_LIST_RESET(name) name.count = 0

static inline void __GCItemListFree(GCItemList* list) {
  free(list->items);
}

#define GC_LIST_FREE(name) __GCItemListFree(&name)

static inline void __GCItemListSwap(GCItemList* list1, GCItemList* list2) {
  GCItemList list = *list1;
  *list1 = *list2;
  *list2 = list;
}

#define GC_LIST_SWAP(name1, name2) __GCItemListSwap(&name1, &name2)

#pragma mark - GCPointerList

typedef struct {
  void** pointers;
  size_t max;
  size_t count;
} GCPointerList;

static inline void __GCPointerListInitialize(GCPointerList* list, size_t initialSize) {
  list->count = 0;
  list->max = initialSize;
#ifdef __clang_analyzer__
  list->max += 1;  // Prevent clang from complaining about calling malloc() with a size of 0
#endif
  list->pointers = malloc(list->max * sizeof(void*));
}

#define GC_POINTER_LIST_INITIALIZE(name, initialSize) __GCPointerListInitialize(&name, initialSize)

#define GC_POINTER_LIST_ALLOCATE(name, initialSize) \
  __block GCPointerList name; \
  GC_POINTER_LIST_INITIALIZE(name, initialSize)

#define GC_POINTER_LIST_ROOT(name) name.pointers

#define GC_POINTER_LIST_COUNT(name) name.count

#define GC_POINTER_LIST_MAX(name) name.max

#define GC_POINTER_LIST_GET(name, index) name.pointers[index]

static inline void __GCPointerListAppend(GCPointerList* list, void* pointer) {
  if (list->count == list->max) {
    list->max *= 2;
#ifdef __clang_analyzer__
    list->max += 1;  // Prevent clang from complaining about calling realloc() with a size of 0
#endif
    list->pointers = realloc(list->pointers, list->max * sizeof(void*));
  }
  list->pointers[list->count] = pointer;
  list->count += 1;
}

#define GC_POINTER_LIST_APPEND(name, pointer) __GCPointerListAppend(&name, pointer)

static inline void __GCPointerListPrepend(GCPointerList* list, void* pointer) {
  if (list->count == list->max) {
    list->max *= 2;
#ifdef __clang_analyzer__
    list->max += 1;  // Prevent clang from complaining about calling realloc() with a size of 0
#endif
    list->pointers = realloc(list->pointers, list->max * sizeof(void*));
  }
  for (size_t i = list->count; i > 0; --i) {
    list->pointers[i] = list->pointers[i - 1];
  }
  list->pointers[0] = pointer;
  list->count += 1;
}

#define GC_POINTER_LIST_PREPEND(name, pointer) __GCPointerListPrepend(&name, pointer)

static inline void __GCPointerListRemove(GCPointerList* list, size_t index) {
  list->count -= 1;
  for (size_t i = index; i < list->count; ++i) {
    list->pointers[i] = list->pointers[i + 1];
  }
}

#define GC_POINTER_LIST_REMOVE(name, index) __GCPointerListRemove(&name, index)

static inline void* __GCPointerListPop(GCPointerList* list) {
  list->count -= 1;
  return list->pointers[list->count];
}

#define GC_POINTER_LIST_POP(name) __GCPointerListPop(&name)

static inline BOOL __GCPointerListContains(GCPointerList* list, void* pointer) {
  for (size_t i = 0; i < list->count; ++i) {
    if (list->pointers[i] == pointer) {
      return YES;
    }
  }
  return NO;
}

#define GC_POINTER_LIST_CONTAINS(name, pointer) __GCPointerListContains(&name, pointer)

#define GC_POINTER_LIST_FOR_LOOP_VARIABLE(name, variable) \
  variable = GC_POINTER_LIST_GET(name, 0); \
  for (size_t __##variable = 0; (__##variable < name.count) && (variable = GC_POINTER_LIST_GET(name, __##variable), 1); ++__##variable)

#define GC_POINTER_LIST_FOR_LOOP(name, type, variable) \
  type variable; \
  GC_POINTER_LIST_FOR_LOOP_VARIABLE(name, variable)

#define GC_POINTER_LIST_REVERSE_FOR_LOOP(name, type, variable) \
  type variable = name.count ? GC_POINTER_LIST_GET(name, name.count - 1) : NULL; \
  for (ssize_t __##variable = name.count - 1; (__##variable >= 0) && (variable = GC_POINTER_LIST_GET(name, __##variable), 1); --__##variable)

#define GC_POINTER_LIST_RESET(name) name.count = 0

static inline void __GCPointerListFree(GCPointerList* list) {
  free(list->pointers);
}

#define GC_POINTER_LIST_FREE(name) __GCPointerListFree(&name)

static inline void __GCPointerListSwap(GCPointerList* list1, GCPointerList* list2) {
  GCPointerList list = *list1;
  *list1 = *list2;
  *list2 = list;
}

#define GC_POINTER_LIST_SWAP(name1, name2) __GCPointerListSwap(&name1, &name2)
