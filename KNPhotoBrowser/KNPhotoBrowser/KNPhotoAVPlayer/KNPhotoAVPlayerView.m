//
//  KNPhotoAVPlayerView.m
//  KNPhotoBrowser
//
//  Created by LuKane on 2019/6/14.
//  Copyright © 2019 LuKane. All rights reserved.
//

#import "KNPhotoAVPlayerView.h"
#import "KNPhotoAVPlayerActionView.h"
#import "KNPhotoAVPlayerActionBar.h"

@interface KNPhotoAVPlayerView ()<KNPhotoAVPlayerActionViewDelegate,KNPhotoAVPlayerActionBarDelegate>

@property (nonatomic,strong) AVPlayer       *player;
@property (nonatomic,strong) AVPlayerItem   *item;

@property (nonatomic,strong) UIImageView *tempImgView;

@property (nonatomic,weak  ) KNPhotoAVPlayerActionView  *actionView;
@property (nonatomic,weak  ) KNPhotoAVPlayerActionBar   *actionBar;

@property (nonatomic,assign) NSTimeInterval  bufferTime;
@property (nonatomic,assign) BOOL  isPlaying;
@property (nonatomic,assign) BOOL  isGettotalPlayTime;

@property (nonatomic,assign) BOOL  isAddObserver;

@end

@implementation KNPhotoAVPlayerView

//- (UIScrollView *)scrollView{
//    if (!_scrollView) {
//        _scrollView = [[UIScrollView alloc] init];
//        [_scrollView setClipsToBounds:true];
//    }
//    return _scrollView;
//}

- (UIImageView *)tempImgView{
    if (!_tempImgView) {
        _tempImgView = [[UIImageView alloc] initWithFrame:self.bounds];
        _tempImgView.contentMode = UIViewContentModeScaleAspectFit;
    }
    return _tempImgView;
}
- (UIView *)playerView{
    if (!_playerView) {
        _playerView = [[UIView alloc] initWithFrame:self.bounds];
        [_playerView setBackgroundColor:UIColor.clearColor];
    }
    return _playerView;
}

- (instancetype)initWithFrame:(CGRect)frame{
    if (self = [super initWithFrame:frame]) {
        [self setBackgroundColor:UIColor.clearColor];
    }
    return self;
}

- (void)playerWithURL:(NSString *)url
          placeHolder:(UIImage *_Nullable)placeHolder{
    self.url = url;
    self.placeHolder = placeHolder;
    
    [self removeAVPlayer];
    
    self.item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:self.url]];
    
    [self setupPlayer];
    [self setupActionView];
}

- (void)removeAVPlayer{
    
    [self removeAllObservers];
    
    [self.player pause];
    self.player = nil;
    self.playerLayer = nil;
    [self.playerView removeFromSuperview];
    self.playerView = nil;
    [self.actionView removeFromSuperview];
    [self.actionBar removeFromSuperview];
    [self.tempImgView removeFromSuperview];
    self.tempImgView = nil;
    self.item = nil;
}

- (void)stopPlay{
    if (self.player) {
        [self.player pause];
        [self videoDidPlayToEndTime];
        
        [_actionView setIsBuffering:false];
        [_actionView setIsPlaying:false];
        [_actionBar setHidden:true];
    }
    self.isPlaying = false;
    self.isAddObserver = false;
}

- (void)pausePlay{
    if (self.player) {
        [self.player pause];
        
        [_actionView setIsBuffering:false];
        [_actionView setIsPlaying:false];
        [_actionBar setHidden:true];
    }
    self.isPlaying = false;
}

/**
 player and views
 */
- (void)setupPlayer{
    self.player = [AVPlayer playerWithPlayerItem:self.item];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    [self.playerView.layer addSublayer:self.playerLayer];
    
    if (self.placeHolder) {
        self.tempImgView.image = self.placeHolder;
    }
    [self addSubview:self.tempImgView];
    
    [self addSubview:self.playerView];
}

/**
 actionView for action
 */
- (void)setupActionView{
    KNPhotoAVPlayerActionView *actionView = [[KNPhotoAVPlayerActionView alloc] initWithFrame:self.bounds];
    [actionView setDelegate:self];
    [actionView setIsBuffering:false];
    [actionView setIsPlaying:false];
    [self addSubview:actionView];
    _actionView = actionView;
    
    KNPhotoAVPlayerActionBar *actionBar = [[KNPhotoAVPlayerActionBar alloc] initWithFrame:self.bounds];
    [actionBar setBackgroundColor:[UIColor colorWithRed:45/255.0 green:45/255.0 blue:45/255.0 alpha:1]];
    [actionBar setDelegate:self];
    [actionBar setHidden:true];
    [actionBar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(actionBarDidClick)]];
    [self addSubview:actionBar];
    _actionBar = actionBar;
}

/**
 observer for item
 */
- (void)setupItemObserver{
    [self.item addObserver:self
                forKeyPath:@"status"
                   options:NSKeyValueObservingOptionNew
                   context:nil];
    [self.item addObserver:self
                forKeyPath:@"loadedTimeRanges"
                   options:NSKeyValueObservingOptionNew
                   context:nil];
    
    __weak typeof(self) weakself = self;
    [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        if (CMTimeGetSeconds(time) == weakself.actionBar.allDuration) {
            [weakself videoDidPlayToEndTime];
            weakself.actionBar.currentTime = 0;
        }else{
            weakself.actionBar.currentTime = CMTimeGetSeconds(time);
        }
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(videoDidPlayToEndTime)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    
    if (![object isKindOfClass:[AVPlayerItem class]]) return;
    
    if ([keyPath isEqualToString:@"status"]) { // play
        if (_player.currentItem.status == AVPlayerStatusReadyToPlay) {
            [self addPeriodicTimeObserver];
        }
    }else if ([keyPath isEqualToString:@"loadedTimeRanges"]) { // buffering
        _bufferTime = [self effectiveBufferedTime];
        if (!_isGettotalPlayTime) {
            _isGettotalPlayTime = true;
            _actionBar.allDuration = CMTimeGetSeconds(_player.currentItem.duration);
        }
        
        if (_actionBar.currentTime <= _actionBar.allDuration - 7) {
            if (_bufferTime <= _actionBar.currentTime + 5) {
                [_actionBar setIsPlaying:false];
                
                [_actionView setIsBuffering:true];
                [_actionView setIsPlaying:false];
            }else{
                [_actionBar setIsPlaying:true];
                [_actionView setIsPlaying:true];
                
                [_actionView setIsBuffering:false];
            }
        }else{
            [_actionBar setIsPlaying:true];
            [_actionView setIsPlaying:true];
            [_actionView setIsBuffering:false];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

/**
 get current effect buffer time
 
 @return time
 */
- (NSTimeInterval)effectiveBufferedTime{
    NSArray *timeRanges = [[self.player currentItem] loadedTimeRanges];
    CMTimeRange range = [[timeRanges firstObject] CMTimeRangeValue];
    NSTimeInterval startTime = CMTimeGetSeconds(range.start);
    NSTimeInterval duration  = CMTimeGetSeconds(range.duration);
    return startTime + duration;
}

- (void)videoDidPlayToEndTime{
    _isGettotalPlayTime = false;
    
    if (_player) {
        __weak typeof(self) weakself = self;
        [_player seekToTime:CMTimeMake(1, 1) completionHandler:^(BOOL finished) {
            if (finished) {
                weakself.actionBar.currentTime = 0;
                [weakself.actionBar setIsPlaying:false];
                [weakself.actionView setIsPlaying:false];
            }
        }];
    }
}

/**
 add observer for current video speed
 */
- (void)addPeriodicTimeObserver{
    
}

- (void)layoutSubviews{
    [super layoutSubviews];
    self.playerLayer.frame  = self.bounds;
    self.playerView.frame   = self.bounds;
    self.actionView.frame   = self.bounds;
    self.tempImgView.frame  = self.bounds;
    self.actionBar.frame    = CGRectMake(15, self.frame.size.height - 50, self.frame.size.width - 30, 30);
}

/****************************** == Delegate == ********************************/
/**
 actionView's Pause imageView
 */
- (void)photoAVPlayerActionViewPauseOrStop{
    if (self.player) {
        
        if (self.isAddObserver == false) {
            [self setupItemObserver];
            self.isAddObserver = true;
        }
        
        [self.player play];
        self.isPlaying = true;
        
        [_actionBar setIsPlaying:true];
        [_actionView setIsPlaying:true];
    }
}
/**
 actionView's dismiss imageView
 */
- (void)photoAVPlayerActionViewDismiss{
    if ([_delegate respondsToSelector:@selector(photoAVPlayerViewDismiss)]) {
        [_delegate photoAVPlayerViewDismiss];
    }
}
/**
 actionView
 */
- (void)photoAVPlayerActionViewDidClickIsHidden:(BOOL)isHidden{
    if (self.isPlaying) {
        [_actionBar setHidden:isHidden];
    }
}

/****************************** == Delegate == ********************************/
- (void)actionBarDidClick{
    
}
- (void)photoAVPlayerActionBarClickWithIsPlay:(BOOL)isNeedPlay{
    if (isNeedPlay) {
        [_player play];
        [_actionView setIsPlaying:true];
        [_actionBar setIsPlaying:true];
    }else{
        [_player pause];
        [_actionView setIsPlaying:false];
        [_actionBar setIsPlaying:false];
    }
}
- (void)photoAVPlayerActionBarChangeValue:(float)value{
    if (self.player) {
        CMTime startTime = CMTimeMakeWithSeconds(value, self.player.currentTime.timescale);
        CMTimeShow(startTime);
        __weak typeof(self) weakself = self;
        AVPlayer *player = self.player;
        [self.player seekToTime:startTime toleranceBefore:CMTimeMake(1, 1000) toleranceAfter:CMTimeMake(1, 1000) completionHandler:^(BOOL finished) {
            if(finished == true && weakself.player == player){
                [player play];
                [weakself.actionBar setIsPlaying:true];
                [weakself.actionView setIsPlaying:true];
            }
        }];
    }
}

- (void)dealloc{
    
    [self removeAllObservers];
    if(self.player){
        [self.player pause];
        self.player = nil;
        self.playerLayer = nil;
    }
}

- (void)removeAllObservers{
    if (self.item && self.isAddObserver == true) {
        [self.item removeObserver:self forKeyPath:@"status"];
        [self.item removeObserver:self forKeyPath:@"loadedTimeRanges"];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:self.player.currentItem];
    }
}

@end
