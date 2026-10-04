#import <UIKit/UIKit.h>
#import "KCModels.h"

// A category: its picture and numbers on top, below the live channels (grid) or this week's top clips (list)
@interface KCCategoryViewController : UIViewController
- (instancetype)initWithCategory:(KCCategory *)category;
@end
