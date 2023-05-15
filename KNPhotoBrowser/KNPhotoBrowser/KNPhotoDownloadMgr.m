//
//  KNPhotoDownloadMgr.m
//  KNPhotoBrowser
//
//  Created by LuKane on 2019/7/29.
//  Copyright © 2019 LuKane. All rights reserved.
//

#import "KNPhotoDownloadMgr.h"
#import <CommonCrypto/CommonDigest.h>

@interface KNPhotoDownloadMgr(){
    NSURLSessionDownloadTask *_downloadTask;
}

@property (nonatomic,copy  ) PhotoDownLoadBlock downloadBlock;
@property (nonatomic,strong) KNPhotoItems *item;
@property (nonatomic,strong) KNPhotoItems *tempItem;

@end

@implementation KNPhotoDownloadMgr

static KNPhotoDownloadMgr *_mgr = nil;

+ (instancetype)shareInstance{
    if (_mgr == nil) {
        _mgr = [[KNPhotoDownloadMgr alloc] init];
    }
    return _mgr;
}
+ (instancetype)allocWithZone:(struct _NSZone *)zone{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _mgr = [super allocWithZone:zone];
    });
    return _mgr;
}

- (id)copyWithZone:(NSZone *)zone{
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone{
    return self;
}

- (instancetype)init{
    if (self = [super init]) {
        _filePath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, true) lastObject] stringByAppendingPathComponent:@"KNPhotoBrowserData"];
    }
    return self;
}

- (void)downloadVideoWithPhotoItems:(KNPhotoItems *)photoItems downloadBlock:(PhotoDownLoadBlock)downloadBlock{
    if (photoItems.url == nil) {
        return;
    }
    
    if (_tempItem == photoItems) {
        _downloadBlock(KNPhotoDownloadStateRepeat,0.0);
        return;
    }
    
    _item          = [[KNPhotoItems alloc] init];
    _item.url      = photoItems.url;
    
    _tempItem      = photoItems;
    _downloadBlock = downloadBlock;
    
    [self cancelTask];
    
    if (photoItems.isVideo == true) {
        NSURL *url = [NSURL URLWithString:photoItems.url];
        if ([url.scheme containsString:@"http"]) {
            [self startDownLoadWithURL:url.absoluteString];
        }
    }else {
        _downloadBlock(KNPhotoDownloadStateUnknow,0.0);
    }
}

/// cancel all download task
- (void)cancelTask{
    _item.downloadState = KNPhotoDownloadStateFailure;
    [_downloadTask cancel];
}

- (void)startDownLoadWithURL:(NSString *)url{
    if (_item.downloadState == KNPhotoDownloadStateDownloading) return;
    
    _item.downloadState = KNPhotoDownloadStateDownloading;
    _item.downloadProgress = 0.0;
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    _downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:url]];
    [_downloadTask resume];
}
#pragma mark - NSURLSession Delegate --> NSURLSessionTaskDelegate
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    CGFloat progress = (CGFloat)totalBytesWritten / (CGFloat)totalBytesExpectedToWrite;
    
    if (progress < 0) progress = 0;
    if (progress > 1) progress = 1;
    
    _item.downloadProgress = progress;
    _item.downloadState = KNPhotoDownloadStateDownloading;
    if (_downloadBlock) {
        
#ifdef DEBUG
        NSLog(@"%lld-%lld == > %f",totalBytesWritten,totalBytesExpectedToWrite,progress);
#endif
        _downloadBlock(KNPhotoDownloadStateDownloading,progress);
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    _item.downloadState = KNPhotoDownloadStateSuccess;
    _item.downloadProgress = 1.0;
    if (error) {
        _item.downloadState = KNPhotoDownloadStateFailure;
        _item.downloadProgress = 0.0;
    }
    if (_downloadBlock) {
        _downloadBlock(_item.downloadState,_item.downloadProgress);
    }
    _tempItem = nil;
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    
    NSString *file = [_filePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",[self md5:_item.url.lastPathComponent.stringByDeletingPathExtension],_item.url.pathExtension]];
    
    [[NSFileManager defaultManager] copyItemAtURL:location toURL:[NSURL fileURLWithPath:file] error:nil];
}

- (NSString *)md5:(NSString *)str{
    const char *cStr = [str UTF8String];
    unsigned char result[16];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), result); // This is the md5 call
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

@end

@implementation KNPhotoDownloadFileMgr

- (instancetype)init{
    if (self = [super init]) {
        _filePath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, true) lastObject] stringByAppendingPathComponent:@"KNPhotoBrowserData"];
    }
    return self;
}

/// check is contain video or not
- (BOOL)startCheckIsExistVideo:(KNPhotoItems *)photoItems {
    if (photoItems == nil || photoItems.url == nil) {
        return false;
    }
    
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    
    BOOL isDir = false;
    BOOL existed = [fileMgr fileExistsAtPath:_filePath isDirectory:&isDir];
    
    if (!(isDir && existed)) {
        [fileMgr createDirectoryAtPath:_filePath withIntermediateDirectories:true attributes:nil error:nil];
        return false;
    }else {
        NSString *path = [_filePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",[self md5:photoItems.url.lastPathComponent.stringByDeletingPathExtension],photoItems.url.pathExtension]];
        return [fileMgr fileExistsAtPath:path];
    }
}

/// get video filepath , but it must download before
- (NSString *)startGetFilePath:(KNPhotoItems *)photoItems {
    NSString *path = [_filePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",[self md5:photoItems.url.lastPathComponent.stringByDeletingPathExtension],photoItems.url.pathExtension]];
    return path;
}

- (NSString *)md5:(NSString *)str{
    const char *cStr = [str UTF8String];
    unsigned char result[16];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), result); // This is the md5 call
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

/// remove video by photoItems
/// @param photoItems photoItems
- (void)removeVideoByPhotoItems:(KNPhotoItems *)photoItems{
    if (photoItems == nil) {
        return;
    }
    [self removeVideoByURLString:photoItems.url];
}

/// remove video by url string
/// @param urlString url string
- (void)removeVideoByURLString:(NSString *)urlString{
    if (urlString == nil) {
        return;
    }
    if ([urlString stringByReplacingOccurrencesOfString:@" " withString:@""].length == 0) {
        return;
    }
    
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    
    BOOL isDir = false;
    BOOL existed = [fileMgr fileExistsAtPath:_filePath isDirectory:&isDir];
    
    if ((isDir && existed)) {
        NSError *err;
        NSString *path = [_filePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@",[self md5:urlString.lastPathComponent.stringByDeletingPathExtension],urlString.pathExtension]];
        [fileMgr removeItemAtPath:path error:&err];
    }
}

/// remove all video
- (void)removeAllVideo{
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:_filePath];
    for (NSString *fileName in enumerator) {
        [[NSFileManager defaultManager] removeItemAtPath:[_filePath stringByAppendingPathComponent:fileName] error:nil];
    }
}

- (void)removeExpiredVideoData{
    dispatch_async(dispatch_queue_create("BFDeleteVideo", DISPATCH_QUEUE_CONCURRENT), ^{
        NSURL *diskCacheURL = [NSURL fileURLWithPath:self->_filePath isDirectory:YES];
        //最后修改的时间
        NSURLResourceKey cacheContentDateKey = NSURLContentModificationDateKey;
        //NSURLTotalFileAllocatedSizeKey判断URL目录中所分配的空间大小
        NSArray<NSString *> *resourceKeys = @[NSURLIsDirectoryKey, cacheContentDateKey, NSURLTotalFileAllocatedSizeKey];
        NSDirectoryEnumerator *fileEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:diskCacheURL
                                                   includingPropertiesForKeys:resourceKeys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:NULL];
    //    NSDate *expirationDate = (maxDiskAge < 0) ? nil: [NSDate dateWithTimeIntervalSinceNow:-maxDiskAge];
        NSMutableDictionary<NSURL *, NSDictionary<NSString *, id> *> *cacheFiles = [NSMutableDictionary dictionary];
        NSUInteger currentCacheSize = 0;
        NSMutableArray<NSURL *> *urlsToDelete = [[NSMutableArray alloc] init];
        for (NSURL *fileURL in fileEnumerator) {
            NSError *error;
            NSDictionary<NSString *, id> *resourceValues = [fileURL resourceValuesForKeys:resourceKeys error:&error];
            if (error || !resourceValues || [resourceValues[NSURLIsDirectoryKey] boolValue]) {
                continue;
            }

//            NSDate *modifiedDate = resourceValues[cacheContentDateKey];
    //        if (expirationDate && [[modifiedDate laterDate:expirationDate] isEqualToDate:expirationDate]) {
    //            [urlsToDelete addObject:fileURL];
    //            continue;
    //        }
            NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
            currentCacheSize += totalAllocatedSize.unsignedIntegerValue;
            cacheFiles[fileURL] = resourceValues;
        }

        for (NSURL *fileURL in urlsToDelete) {
            [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        }
        NSUInteger maxDiskSize = 1024 * 1024 * 400;
        NSArray<NSURL *> *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                                 usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                     return [obj1[cacheContentDateKey] compare:obj2[cacheContentDateKey]];
                                                                 }];
        if (maxDiskSize > 0 && currentCacheSize > maxDiskSize) {
            const NSUInteger desiredCacheSize = maxDiskSize / 2;
            NSArray<NSURL *> *sortedFiles = [cacheFiles keysSortedByValueWithOptions:NSSortConcurrent
                                                                     usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                                                         return [obj1[cacheContentDateKey] compare:obj2[cacheContentDateKey]];
                                                                     }];
            for (NSURL *fileURL in sortedFiles) {
                if ([[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil]) {
                    NSDictionary<NSString *, id> *resourceValues = cacheFiles[fileURL];
                    NSNumber *totalAllocatedSize = resourceValues[NSURLTotalFileAllocatedSizeKey];
                    currentCacheSize -= totalAllocatedSize.unsignedIntegerValue;

                    if (currentCacheSize < desiredCacheSize) {
                        break;
                    }
                }
            }
        }
    });
}
@end

