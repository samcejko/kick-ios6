#import "KCSettingsViewController.h"
#import "KCChoiceViewController.h"
#import "KCSettings.h"
#import "KCTheme.h"
#import "KCTLSSocket.h"
#import "KCHTTP.h"
#import "KCImageLoader.h"
#import "KCUtils.h"
#import "KCCommon.h"

typedef NS_ENUM(NSInteger, KCSettingsSection) {
    KCSectionPlayback = 0,
    KCSectionChat,
    KCSectionAppearance,
    KCSectionAdvanced,
    KCSectionAbout,
    KCSectionCount,
};

@interface KCSettingsViewController ()
@property (nonatomic, copy) NSString *cacheSizeText;
@property (nonatomic, copy) NSString *connectionTestText;
@property (nonatomic, strong) KCHTTPTask *testTask;
@end

@implementation KCSettingsViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.title = L(@"Settings");
    return self;
}

- (void)dealloc
{
    [_testTask cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:KCThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyTheme];
    [self.tableView reloadData];
    __weak KCSettingsViewController *weakSelf = self;
    [[KCImageLoader shared] diskUsage:^(unsigned long long bytes) {
        weakSelf.cacheSizeText = [KCUtils formatFileSize:bytes];
        [weakSelf.tableView reloadData];
    }];
}

- (void)applyTheme
{
    KCTheme *t = [KCTheme shared];
    [t applyToTableView:self.tableView];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    [self.tableView reloadData];
}

#pragma mark - Helpers

- (NSInteger)tagForSection:(NSInteger)section row:(NSInteger)row
{
    return section * 100 + row;
}

- (UISwitch *)switchOn:(BOOL)on tag:(NSInteger)tag
{
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = on;
    sw.tag = tag;
    sw.onTintColor = [[KCTheme shared] switchTintColor];
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UISegmentedControl *)segmentedWithItems:(NSArray *)items selected:(NSInteger)selected tag:(NSInteger)tag width:(CGFloat)width
{
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:items];
    seg.segmentedControlStyle = UISegmentedControlStyleBar;
    seg.frame = CGRectMake(0, 0, width, 30);
    seg.selectedSegmentIndex = selected;
    seg.tag = tag;
    [seg addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    return seg;
}

+ (NSArray *)qualityKeys
{
    return @[ KCQualityAuto, KCQualitySource, @"1080", @"720", @"480", @"360", @"160", KCQualityAudio ];
}

+ (NSString *)qualityTitle:(NSString *)key
{
    if ([key isEqualToString:KCQualityAuto]) return L(@"Automatic");
    if ([key isEqualToString:KCQualitySource]) return L(@"Source (best)");
    if ([key isEqualToString:KCQualityAudio]) return L(@"Audio only");
    return [NSString stringWithFormat:@"%@p", key];
}

#pragma mark - Table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return KCSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch ((KCSettingsSection)section) {
        case KCSectionPlayback: return 3;
        case KCSectionChat: return 6;
        case KCSectionAppearance: return 1;
        case KCSectionAdvanced: return 3;
        case KCSectionAbout: return 4;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch ((KCSettingsSection)section) {
        case KCSectionPlayback: return L(@"Playback");
        case KCSectionChat: return L(@"Chat");
        case KCSectionAppearance: return L(@"Appearance");
        case KCSectionAdvanced: return L(@"Advanced");
        case KCSectionAbout: return L(@"About");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch ((KCSettingsSection)section) {
        case KCSectionPlayback: return L(@"This device decodes H.264 up to 1080p at 30 frames per second; renditions beyond that are left out of \"Automatic\".");
        case KCSectionChat: return L(@"The chat is read without an account, so writing in it is not possible.");
        case KCSectionAdvanced: return L(@"Turn certificate verification off only if the device clock is wrong or the certificate bundle is outdated.");
        case KCSectionAbout: return L(@"Kicker is an unofficial app. It is not made by Kick and has no connection to it.");
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == KCSectionAdvanced && indexPath.row == 2) return 56;
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    KCTheme *t = [KCTheme shared];
    NSInteger sec = indexPath.section, row = indexPath.row;
    NSInteger tag = [self tagForSection:sec row:row];
    BOOL subtitle = sec == KCSectionAdvanced && row == 2;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:subtitle ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:subtitle ? 12 : 15];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    CGFloat segW = KCIsPad() ? 260 : 190;

    switch ((KCSettingsSection)sec) {
        case KCSectionPlayback:
            if (row == 0) {
                cell.textLabel.text = L(@"Quality");
                cell.detailTextLabel.text = [KCSettingsViewController qualityTitle:[KCSettings preferredQuality]];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Sound in background");
                cell.accessoryView = [self switchOn:[KCSettings backgroundAudio] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = L(@"Keep screen on");
                cell.accessoryView = [self switchOn:[KCSettings keepScreenOn] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            break;
        case KCSectionChat:
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (row == 0) {
                cell.textLabel.text = L(@"Text size");
                cell.accessoryView = [self segmentedWithItems:@[ L(@"Small"), L(@"Medium"), L(@"Large") ] selected:[KCSettings chatFontSize] tag:tag width:segW];
            } else if (row == 1) {
                cell.textLabel.text = L(@"Timestamps");
                cell.accessoryView = [self switchOn:[KCSettings chatTimestamps] tag:tag];
            } else if (row == 2) {
                cell.textLabel.text = L(@"Animated emotes");
                cell.accessoryView = [self switchOn:[KCSettings animatedEmotes] tag:tag];
            } else if (row == 3) {
                cell.textLabel.text = L(@"7TV emotes");
                cell.accessoryView = [self switchOn:[KCSettings thirdPartyEmotes] tag:tag];
            } else if (row == 4) {
                cell.textLabel.text = L(@"Show deleted messages");
                cell.accessoryView = [self switchOn:[KCSettings showDeletedMessages] tag:tag];
            } else {
                cell.textLabel.text = L(@"Lines between messages");
                cell.accessoryView = [self switchOn:[KCSettings chatSeparators] tag:tag];
            }
            break;
        case KCSectionAppearance:
            cell.textLabel.text = L(@"Theme");
            cell.accessoryView = [self segmentedWithItems:@[ L(@"Light"), L(@"Dark") ] selected:t.isDark ? 1 : 0 tag:tag width:KCIsPad() ? 200 : 150];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case KCSectionAdvanced:
            if (row == 0) {
                cell.textLabel.text = L(@"Verify certificates");
                cell.accessoryView = [self switchOn:[KCSettings verifyTLS] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Clear image cache");
                cell.detailTextLabel.text = self.cacheSizeText ?: @"";
            } else {
                cell.textLabel.text = L(@"Connection test");
                cell.detailTextLabel.text = self.connectionTestText ?: L(@"Tap to test the connection to Kick");
            }
            break;
        case KCSectionAbout:
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (row == 0) {
                cell.textLabel.text = L(@"Version");
                cell.detailTextLabel.text = [KCUtils appVersion];
            } else if (row == 1) {
                cell.textLabel.text = L(@"Author");
                cell.detailTextLabel.text = @"samcejko";
            } else if (row == 2) {
                cell.textLabel.text = L(@"Root certificates");
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)[KCTLSSocket caCertificateCount]];
            } else {
                cell.textLabel.text = L(@"Device");
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · iOS %@", [KCUtils deviceModel], [UIDevice currentDevice].systemVersion];
            }
            break;
        default:
            break;
    }
    [t styleCell:cell];
    return cell;
}

#pragma mark - Controls

- (void)switchChanged:(UISwitch *)sw
{
    NSInteger sec = sw.tag / 100, row = sw.tag % 100;
    if (sec == KCSectionPlayback && row == 1) [KCSettings setBackgroundAudio:sw.on];
    else if (sec == KCSectionPlayback && row == 2) [KCSettings setKeepScreenOn:sw.on];
    else if (sec == KCSectionChat && row == 1) [KCSettings setChatTimestamps:sw.on];
    else if (sec == KCSectionChat && row == 2) { [KCSettings setAnimatedEmotes:sw.on]; [KCImageLoader shared].animationAllowed = sw.on; [[KCImageLoader shared] clearMemory]; }
    else if (sec == KCSectionChat && row == 3) [KCSettings setThirdPartyEmotes:sw.on];
    else if (sec == KCSectionChat && row == 4) [KCSettings setShowDeletedMessages:sw.on];
    else if (sec == KCSectionChat && row == 5) [KCSettings setChatSeparators:sw.on];
    else if (sec == KCSectionAdvanced && row == 0) [KCSettings setVerifyTLS:sw.on];
    [KCSettings save];
}

- (void)segmentChanged:(UISegmentedControl *)seg
{
    NSInteger sec = seg.tag / 100, row = seg.tag % 100;
    if (sec == KCSectionChat && row == 0) [KCSettings setChatFontSize:seg.selectedSegmentIndex];
    else if (sec == KCSectionAppearance) [[KCTheme shared] setDark:seg.selectedSegmentIndex == 1];
    [KCSettings save];
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger sec = indexPath.section, row = indexPath.row;
    if (sec == KCSectionPlayback && row == 0) {
        KCChoiceViewController *vc = [[KCChoiceViewController alloc] init];
        vc.title = L(@"Quality");
        NSArray *keys = [KCSettingsViewController qualityKeys];
        NSMutableArray *titles = [NSMutableArray array];
        for (NSString *k in keys) [titles addObject:[KCSettingsViewController qualityTitle:k]];
        vc.titles = titles;
        vc.subtitles = @[ L(@"The player picks what the connection allows, up to what the device decodes."), L(@"The streamer's own quality, when the device can decode it."),
                          @"", @"", @"", @"", @"", L(@"Just the sound, for the background.") ];
        NSUInteger idx = [keys indexOfObject:[KCSettings preferredQuality]];
        vc.selectedIndex = idx == NSNotFound ? 0 : (NSInteger)idx;
        vc.completion = ^(NSInteger index) {
            [KCSettings setPreferredQuality:keys[(NSUInteger)index]];
            [KCSettings save];
        };
        [self.navigationController pushViewController:vc animated:YES];
    } else if (sec == KCSectionAdvanced && row == 1) {
        self.cacheSizeText = L(@"Clearing…");
        [tableView reloadData];
        __weak KCSettingsViewController *weakSelf = self;
        [[KCImageLoader shared] clearDiskWithCompletion:^{
            weakSelf.cacheSizeText = [KCUtils formatFileSize:0];
            [weakSelf.tableView reloadData];
        }];
    } else if (sec == KCSectionAdvanced && row == 2) {
        [self runConnectionTest];
    }
}

- (void)runConnectionTest
{
    if (self.testTask) return;
    self.connectionTestText = L(@"Testing…");
    [self.tableView reloadData];
    NSDate *start = [NSDate date];
    __weak KCSettingsViewController *weakSelf = self;
    self.testTask = [KCHTTP get:@"https://kick.com/api/v1/subcategories?limit=1" headers:nil completion:^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        KCSettingsViewController *s = weakSelf;
        if (!s) return;
        NSTimeInterval dt = -[start timeIntervalSinceNow];
        if (error) s.connectionTestText = error.localizedDescription;
        else s.connectionTestText = [NSString stringWithFormat:L(@"Kick answered (HTTP %ld) in %.1f s"), (long)status, dt];
        s.testTask = nil;
        [s.tableView reloadData];
    }];
}

@end
