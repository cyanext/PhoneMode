#import "PhoneModels.h"

// clang-format off
const Model kModels[]={
  {"iPhone", "iPhone 18 Pro Max",  72.9,158.4,10.3,5.6, CUT_ISLAND,  860,1010, "iPhone 18 系列"},
  {"iPhone", "iPhone 18 Pro",      66.6,144.8,10.3,5.6, CUT_ISLAND,  800, 860, "iPhone 18 系列"},
  {"iPhone", "iPhone 17 Pro Max",  72.9,158.4,10.3,5.6, CUT_ISLAND,  860,1010, "iPhone 17 系列"},
  {"iPhone", "iPhone 17 Pro",      66.6,144.8,10.3,5.6, CUT_ISLAND,  800, 860, "iPhone 17 系列"},
  {"iPhone", "iPhone Air",         69.6,151.1,11.3,5.6, CUT_ISLAND,  830, 920, "iPhone 17 系列"},
  {"iPhone", "iPhone 17",          66.6,144.8,10.3,5.6, CUT_ISLAND,  800, 860, "iPhone 17 系列"},
  {"iPhone", "iPhone 16 Pro Max",  72.9,158.4,10.3,5.6, CUT_ISLAND,  860,1010, "iPhone 16 系列"},
  {"iPhone", "iPhone 16 Pro",      66.6,144.8,10.3,5.6, CUT_ISLAND,  800, 860, "iPhone 16 系列"},
  {"iPhone", "iPhone 16 Plus",     71.2,154.4, 9.8,5.6, CUT_ISLAND,  850, 980, "iPhone 16 系列"},
  {"iPhone", "iPhone 16",          65.1,141.1, 9.8,5.6, CUT_ISLAND,  800, 840, "iPhone 16 系列"},
  {"iPhone", "iPhone 16e",         64.6,139.8, 7.8,5.6, CUT_NOTCH,   800, 860, "iPhone 16 系列"},
  {"iPhone", "iPhone 15 Pro Max",  71.2,154.4, 9.8,5.6, CUT_ISLAND,  850, 980, "iPhone 15 系列"},
  {"iPhone", "iPhone 15 Pro",      65.1,141.1, 9.8,5.6, CUT_ISLAND,  800, 840, "iPhone 15 系列"},
  {"iPhone", "iPhone 15 Plus",     71.2,154.4, 9.8,5.6, CUT_ISLAND,  850, 980, "iPhone 15 系列"},
  {"iPhone", "iPhone 15",          65.1,141.1, 9.8,5.6, CUT_ISLAND,  800, 840, "iPhone 15 系列"},
  {"iPhone", "iPhone 14 Pro Max",  71.2,154.4, 9.8,5.6, CUT_ISLAND,  850, 980, "iPhone 14 系列"},
  {"iPhone", "iPhone 14 Pro",      65.1,141.1, 9.8,5.6, CUT_ISLAND,  800, 840, "iPhone 14 系列"},
  {"iPhone", "iPhone 14 Plus",     71.2,154.1, 7.8,5.7, CUT_NOTCH,   850,1000, "iPhone 14 系列"},
  {"iPhone", "iPhone 14",          64.6,139.8, 7.8,5.6, CUT_NOTCH,   800, 860, "iPhone 14 系列"},
  {"iPhone", "iPhone 13 Pro Max",  71.2,154.1, 7.8,5.7, CUT_NOTCH,   850,1000, "iPhone 13 系列"},
  {"iPhone", "iPhone 13 Pro",      64.6,139.8, 7.8,5.6, CUT_NOTCH,   800, 860, "iPhone 13 系列"},
  {"iPhone", "iPhone 13",          64.6,139.8, 7.8,5.6, CUT_NOTCH,   800, 860, "iPhone 13 系列"},
  {"iPhone", "iPhone 13 mini",     57.6,124.9, 8.0,5.4, CUT_NOTCH,   800, 750, "iPhone 13 系列"},
  {"iPhone", "iPhone 12 Pro Max",  71.2,154.1, 7.8,5.7, CUT_NOTCH,   850,1000, "iPhone 12 系列"},
  {"iPhone", "iPhone 12 Pro",      64.6,139.8, 7.8,5.6, CUT_NOTCH,   800, 860, "iPhone 12 系列"},
  {"iPhone", "iPhone 12",          64.6,139.8, 7.8,5.6, CUT_NOTCH,   800, 860, "iPhone 12 系列"},
  {"iPhone", "iPhone 12 mini",     57.6,124.9, 8.0,5.4, CUT_NOTCH,   800, 750, "iPhone 12 系列"},
  {"iPhone", "iPhone 11 Pro Max",  68.9,149.1, 7.3,5.7, CUT_NOTCH,   820, 940, "iPhone 11 系列"},
  {"iPhone", "iPhone 11 Pro",      62.4,135.1, 7.3,5.7, CUT_NOTCH,   800, 830, "iPhone 11 系列"},
  {"iPhone", "iPhone 11",          64.5,139.6, 7.5,5.3, CUT_NOTCH,   800, 860, "iPhone 11 系列"},
  {"iPhone", "iPhone XS Max",      68.9,149.1, 7.3,5.7, CUT_NOTCH,   820, 940, "iPhone XS、XR、X"},
  {"iPhone", "iPhone XS",          62.4,135.1, 7.3,5.7, CUT_NOTCH,   800, 830, "iPhone XS、XR、X"},
  {"iPhone", "iPhone XR",          64.5,139.6, 7.5,5.3, CUT_NOTCH,   800, 860, "iPhone XS、XR、X"},
  {"iPhone", "iPhone X",           62.4,135.1, 7.3,5.7, CUT_NOTCH,   800, 830, "iPhone XS、XR、X"},
  {"HUAWEI",   "HUAWEI Pura X View",      82.6,139.6, 7.7,5.7, CUT_HOLE,    980, 820, NULL},
  {"Android",  "6.7 英寸（20:9）",           69.8,155.2, 7.7,5.7, CUT_HOLE,    830,1010, NULL},
  {"Android",  "6.3 英寸（20:9）",           65.7,145.9, 7.7,5.7, CUT_HOLE,    800, 920, NULL},
};
// clang-format on
const int kModelCount = (int)(sizeof kModels / sizeof kModels[0]);

// 旧版本存下的型号名，读设置和预设时换成现在的名字
static NSString *currentName(NSString *n) {
    NSDictionary *old = @{
        @"Pura X View" : @"HUAWEI Pura X View",
        @"约 6.7 英寸" : @"6.7 英寸（20:9）",
        @"约 6.3 英寸" : @"6.3 英寸（20:9）",
    };
    return old[n] ?: n;
}

int modelIndexByName(NSString *n) {
    n = currentName(n);
    for (int i = 0; i < NMODEL; i++) {
        if ([n isEqualToString:@(kModels[i].name)]) {
            return i;
        }
    }
    return -1;
}

NSArray<NSString *> *groupNames(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < NMODEL; i++) {
        NSString *g = @(kModels[i].group);
        if (![a containsObject:g]) {
            [a addObject:g];
        }
    }
    return a;
}

int groupOfModel(int m) {
    return (int)[groupNames() indexOfObject:@(kModels[m].group)];
}

int firstModelOfGroup(int g) {
    NSString *n = groupNames()[g];
    for (int i = 0; i < NMODEL; i++) {
        if ([n isEqualToString:@(kModels[i].group)]) {
            return i;
        }
    }
    return 0;
}
