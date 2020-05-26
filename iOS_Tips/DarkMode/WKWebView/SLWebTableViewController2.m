//
//  SLWebTableViewController2.m
//  DarkMode
//
//  Created by wsl on 2020/5/25.
//  Copyright © 2020 https://github.com/wsl2ls   ----- . All rights reserved.
//

#import "SLWebTableViewController2.h"
#import <WebKit/WebKit.h>

///动力元素  力的作用对象
@interface DynamicItem : NSObject <UIDynamicItem>
@property (nonatomic, readwrite) CGPoint center;
@property (nonatomic, readonly) CGRect bounds;
@property (nonatomic, readwrite) CGAffineTransform transform;
@end
@implementation DynamicItem
- (instancetype)init {
    self = [super init];
    if (self) {
        _bounds = CGRectMake(0, 0, 1, 1);
    }
    return self;
}
@end

@interface UIScrollView (Demo)
/// Y轴方向的最大的偏移量
- (CGFloat)maxContentOffsetY;
/// 到达底部
- (BOOL)isReachBottom;
/// 到达顶部
- (BOOL)isReachTop;
/// 滚动到顶部
- (void)scrollToTopWithAnimated:(BOOL)animated;
@end
@implementation UIScrollView (Demo)
- (CGFloat)maxContentOffsetY {
    return MAX(0, self.contentSize.height - self.frame.size.height);
}
- (BOOL)isReachBottom {
    return self.contentOffset.y > [self maxContentOffsetY] ||
    fabs(self.contentOffset.y - [self maxContentOffsetY]) < FLT_EPSILON;
}
- (BOOL)isReachTop {
    return self.contentOffset.y <= 0;
}
- (void)scrollToTopWithAnimated:(BOOL)animated {
    [self setContentOffset:CGPointZero animated:animated];
}
@end


@interface SLWebTableViewController2 ()<UITableViewDelegate,UITableViewDataSource, UIDynamicAnimatorDelegate>

@property (nonatomic, strong) WKWebView * webView;
@property (nonatomic, strong) UITableView *tableView;
///啊网页加载进度视图
@property (nonatomic, strong) UIProgressView * progressView;
/// WKWebView 内容的高度  默认屏幕高
@property (nonatomic, assign) CGFloat webContentHeight;

/// self.view拖拽手势
@property(nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
/// 边缘处能上拉或下拉的最大距离
@property(nonatomic) CGFloat bounceDistanceThreshold;

/*  UIKit 动力学/仿真物理学：https://blog.csdn.net/meiwenjie110/article/details/46771299 */
/// 动力装置  启动力
@property(nonatomic, strong) UIDynamicAnimator *dynamicAnimator;
/// 惯性力    手指滑动松开后，scrollView借助于惯性力，以手指松开时的初速度以及设置的resistance动力减速度运动，直至停止
@property(nonatomic, weak) UIDynamicItemBehavior *inertialBehavior;
/// 吸附力   模拟UIScrollView滑到底部或顶部时的回弹效果
@property(nonatomic, weak) UIAttachmentBehavior *bounceBehavior;

@end

@implementation SLWebTableViewController2

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUi];
    [self addKVO];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.progressView removeFromSuperview];
}
- (void)dealloc {
    [self removeKVO];
    NSLog(@"%@释放了",NSStringFromClass(self.class));
}
// 滚动中单击可以停止滚动
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self.dynamicAnimator removeAllBehaviors];
}

#pragma mark - SetupUI
- (void)setupUi {
    self.title = @"WKWebView+UITableView（方案2）";
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.bounceDistanceThreshold = 64;
    [self.view addGestureRecognizer:self.panRecognizer];
    [self.view addSubview:self.webView];
    
}

#pragma mark - Getter
- (UITableView *)tableView {
    if (_tableView == nil) {
        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, SL_kScreenWidth, SL_kScreenHeight) style:UITableViewStyleGrouped];
        _tableView.delegate = self;
        _tableView.dataSource = self;
        _tableView.estimatedRowHeight = 1;
        _tableView.scrollEnabled = NO;
    }
    return _tableView;
}
- (WKWebView *)webView {
    if(_webView == nil){
        //创建网页配置
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        
        _webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, SL_kScreenWidth, SL_kScreenHeight) configuration:config];
        _webView.scrollView.scrollEnabled = NO;
        
        //                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.jianshu.com/p/5cf0d241ae12"]];
        //                [_webView loadRequest:request];
        
        NSString *path = [[NSBundle mainBundle] pathForResource:@"2.html" ofType:nil];
        NSString *htmlString = [[NSString alloc]initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        [_webView loadHTMLString:htmlString baseURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]]];
    }
    return _webView;
}
- (UIProgressView *)progressView {
    if (!_progressView){
        _progressView = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, SL_kScreenWidth, 2)];
        _progressView.tintColor = [UIColor blueColor];
        _progressView.trackTintColor = [UIColor clearColor];
    }
    if (_progressView.superview == nil) {
        [self.navigationController.navigationBar addSubview:_progressView];
    }
    return _progressView;
}
- (UIPanGestureRecognizer *)panRecognizer {
    if (!_panRecognizer) {
        _panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGestureRecognizer:)];
        //        _panRecognizer.delegate = self;
    }
    return _panRecognizer;
}

- (UIDynamicAnimator *)dynamicAnimator {
    if (!_dynamicAnimator) {
        _dynamicAnimator = [[UIDynamicAnimator alloc] initWithReferenceView:self.view];
        _dynamicAnimator.delegate = self;
    }
    return _dynamicAnimator;
}

#pragma mark - KVO
///添加键值对监听
- (void)addKVO {
    //监听网页加载进度
    [self.webView addObserver:self
                   forKeyPath:NSStringFromSelector(@selector(estimatedProgress))
                      options:NSKeyValueObservingOptionNew
                      context:nil];
    //监听网页内容高度
    [self.webView.scrollView addObserver:self
                              forKeyPath:@"contentSize"
                                 options:NSKeyValueObservingOptionNew
                                 context:nil];
}
///移除监听
- (void)removeKVO {
    //移除观察者
    [_webView removeObserver:self
                  forKeyPath:NSStringFromSelector(@selector(estimatedProgress))];
    [_webView.scrollView removeObserver:self
                             forKeyPath:NSStringFromSelector(@selector(contentSize))];
}
//kvo监听 必须实现此方法
-(void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                      context:(void *)context{
    
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(estimatedProgress))]
        && object == _webView) {
        //        NSLog(@"网页加载进度 = %f",_webView.estimatedProgress);
        self.progressView.progress = _webView.estimatedProgress;
        if (_webView.estimatedProgress >= 1.0f) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.progressView.progress = 0;
            });
        }
    }else if ([keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]
              && object == _webView.scrollView && _webContentHeight != _webView.scrollView.contentSize.height) {
        _webContentHeight = _webView.scrollView.contentSize.height;
        NSLog(@"WebViewContentSize = %@",NSStringFromCGSize(_webView.scrollView.contentSize))
    }
}

#pragma mark - EventsHandle
/// 拖拽手势，模拟UIScrollView滑动
- (void)handlePanGestureRecognizer:(UIPanGestureRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            //开始拖动，移除之前所有的动力行为
            [self.dynamicAnimator removeAllBehaviors];
        }
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [recognizer translationInView:self.view];
            //拖动过程中调整scrollView.contentOffset
            [self scrollViewsWithDeltaY:translation.y];
            [recognizer setTranslation:CGPointZero inView:self.view];
        }
            break;
        case UIGestureRecognizerStateEnded: {
            // 这个if是为了避免在拉到边缘时，以一个非常小的初速度松手不回弹的问题
            if (fabs([recognizer velocityInView:self.view].y) < 120) {
                if ([self.tableView isReachTop] &&
                    [self.webView.scrollView isReachTop]) {
                    //顶部
                    [self performBounceForScrollView:self.webView.scrollView isAtTop:YES];
                } else if ([self.tableView isReachBottom] &&
                           [self.webView.scrollView isReachBottom]) {
                    //底部
                    if (self.tableView.frame.size.height < self.view.sl_h) { //tableView不足一屏，webView bounce
                        [self performBounceForScrollView:self.webView.scrollView isAtTop:NO];
                    } else {
                        [self performBounceForScrollView:self.tableView isAtTop:NO];
                    }
                }
                return;
            }
            
            //动力元素 力的操作对象
            DynamicItem *item = [[DynamicItem alloc] init];
            item.center = CGPointZero;
            __block CGFloat lastCenterY = 0;
            UIDynamicItemBehavior *inertialBehavior = [[UIDynamicItemBehavior alloc] initWithItems:@[item]];
            //给item添加初始线速度 手指松开时的速度
            [inertialBehavior addLinearVelocity:CGPointMake(0, -[recognizer velocityInView:self.view].y) forItem:item];
            //减速度  无速度阻尼
            inertialBehavior.resistance = 2;
            __weak typeof(self) weakSelf = self;
            inertialBehavior.action = ^{
                //惯性力 移动的距离
                [weakSelf scrollViewsWithDeltaY:lastCenterY - item.center.y];
                lastCenterY = item.center.y;
            };
            self.inertialBehavior = inertialBehavior;
            [self.dynamicAnimator addBehavior:inertialBehavior];
        }
            break;
        default:
            break;
    }
}

#pragma mark - Help Methods
/// 根据拖拽手势在屏幕上的拖拽距离，调整scrollView.contentOffset
- (void)scrollViewsWithDeltaY:(CGFloat)deltaY {
    if (deltaY < 0) { //上拉
        if ([self.webView.scrollView isReachBottom]) { //webView已滑到底，此时应滑动tableView
            if ([self.tableView isReachBottom]) { //tableView也到底
                if (self.tableView.frame.size.height < self.view.sl_h) { //tableView不足一屏，webView bounce
                    self.tableView.contentOffset = CGPointMake(0, self.tableView.contentSize.height - self.tableView.frame.size.height);
                    CGFloat bounceDelta = MAX(0, (self.bounceDistanceThreshold - fabs(self.webView.scrollView.contentOffset.y - self.webView.scrollView.maxContentOffsetY)) / self.bounceDistanceThreshold) * 0.5;
                    self.webView.scrollView.contentOffset = CGPointMake(0, self.webView.scrollView.contentOffset.y - deltaY * bounceDelta);
                    [self performBounceIfNeededForScrollView:self.webView.scrollView isAtTop:NO];
                } else {
                    CGFloat bounceDelta = MAX(0, (self.bounceDistanceThreshold - fabs(self.tableView.contentOffset.y - self.tableView.maxContentOffsetY)) / self.bounceDistanceThreshold) * 0.5;
                    self.tableView.contentOffset = CGPointMake(0, self.tableView.contentOffset.y - deltaY * bounceDelta);
                    [self performBounceIfNeededForScrollView:self.tableView isAtTop:NO];
                }
            } else {
                self.tableView.contentOffset = CGPointMake(0, MIN(self.tableView.contentOffset.y - deltaY, [self.tableView maxContentOffsetY]));
            }
        } else {
            self.webView.scrollView.contentOffset = CGPointMake(0, MIN(self.webView.scrollView.contentOffset.y - deltaY, [self.webView.scrollView maxContentOffsetY]));
        }
    } else if (deltaY > 0) { //下拉
        if ([self.tableView isReachTop]) { //tableView滑到顶，此时应滑动webView
            if ([self.webView.scrollView isReachTop]) { //webView到顶
                CGFloat bounceDelta = MAX(0, (self.bounceDistanceThreshold - fabs(self.webView.scrollView.contentOffset.y)) / self.bounceDistanceThreshold) * 0.5;
                self.webView.scrollView.contentOffset = CGPointMake(0, self.webView.scrollView.contentOffset.y - deltaY * bounceDelta);
                [self performBounceIfNeededForScrollView:self.webView.scrollView isAtTop:YES];
            } else {
                self.webView.scrollView.contentOffset = CGPointMake(0, MAX(self.webView.scrollView.contentOffset.y - deltaY, 0));
            }
        } else {
            self.tableView.contentOffset = CGPointMake(0, MAX(self.tableView.contentOffset.y - deltaY, 0));
        }
    }
}

//区分滚动到边缘处回弹 和 拉到边缘后以极小的初速度滚动
- (void)performBounceIfNeededForScrollView:(UIScrollView *)scrollView isAtTop:(BOOL)isTop {
    if (self.inertialBehavior) {
        [self performBounceForScrollView:scrollView isAtTop:isTop];
    }
}
//滑动到底部或顶部边界时，执行吸附力/回弹效果
- (void)performBounceForScrollView:(UIScrollView *)scrollView isAtTop:(BOOL)isTop {
    if (!self.bounceBehavior) {
        //移除惯性力
        [self.dynamicAnimator removeBehavior:self.inertialBehavior];
        
        //吸附力操作元素
        DynamicItem *item = [[DynamicItem alloc] init];
        item.center = scrollView.contentOffset;
        //吸附力的锚点Y
        CGFloat attachedToAnchorY = 0;
        if (scrollView == self.webView.scrollView) {
            //顶部时吸附力的Y轴锚点是0  底部时的锚点是Y轴最大偏移量
            attachedToAnchorY = isTop ? 0 : [self.webView.scrollView maxContentOffsetY];
        } else {
            attachedToAnchorY = [self.tableView maxContentOffsetY];
        }
        //吸附力
        UIAttachmentBehavior *bounceBehavior = [[UIAttachmentBehavior alloc] initWithItem:item attachedToAnchor:CGPointMake(0, attachedToAnchorY)];
        //两个吸附点的距离
        bounceBehavior.length = 0;
        //阻尼/缓冲
        bounceBehavior.damping = 1;
        //频率
        bounceBehavior.frequency = 2;
        __weak typeof(bounceBehavior) weakBounceBehavior = bounceBehavior;
        __weak typeof(self) weakSelf = self;
        bounceBehavior.action = ^{
            scrollView.contentOffset = CGPointMake(0, item.center.y);
            //            if (fabs(scrollView.contentOffset.y - attachedToAnchorY) < FLT_EPSILON) {
            //                [weakSelf.dynamicAnimator removeBehavior:weakBounceBehavior];
            //            }
        };
        self.bounceBehavior = bounceBehavior;
        [self.dynamicAnimator addBehavior:bounceBehavior];
    }
}

#pragma mark - UITableViewDelegate,UITableViewDataSource
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 20;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 44;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UILabel *label = [UILabel new];
    label.text = @"评论";
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor orangeColor];
    return label;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.1;
}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"cellId"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cellId"];
    }
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.text = [NSString stringWithFormat:@"第%ld条评论",(long)indexPath.row];
    cell.detailTextLabel.text = @"方案2：";
    return cell;
}

@end