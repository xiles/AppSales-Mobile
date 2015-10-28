//
//  IconManager.m
//  AppSales
//
//  Created by Ole Zorn on 20.07.11.
//  Copyright 2011 omz:software. All rights reserved.
//

#import "IconManager.h"

@interface IconManager ()

- (void)dequeueDownload;

@end

@implementation IconManager

- (id)init
{
    self = [super init];
    if (self) {
		queue = dispatch_queue_create("app icon download", NULL);
		iconCache = [NSMutableDictionary new];
		downloadQueue = [NSMutableArray new];
		
		BOOL isDir = NO;
		[[NSFileManager defaultManager] fileExistsAtPath:[self iconDirectory] isDirectory:&isDir];
		if (!isDir) {
			[[NSFileManager defaultManager] createDirectoryAtPath:[self iconDirectory] withIntermediateDirectories:YES attributes:nil error:NULL];
		}
	}
	return self;
}

+ (id)sharedManager
{
	static id sharedManager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedManager = [[self alloc] init];
	});
	return sharedManager;
}

- (NSString *)iconDirectory
{
	NSString *appSupportPath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject];
	NSString *iconDirectory = [appSupportPath stringByAppendingPathComponent:@"AppIcons"];
	return iconDirectory;
}

- (UIImage *)iconForAppID:(NSString *)appID
{
	if ([appID length] < 4) {
		NSLog(@"Invalid app ID for icon download (%@)", appID);
		return nil;
	}
	UIImage *cachedIcon = [iconCache objectForKey:appID];
	if (cachedIcon) {
		return cachedIcon;
	}
	NSString *iconPath = [[self iconDirectory] stringByAppendingPathComponent:appID];
	UIImage *icon = [[[UIImage alloc] initWithContentsOfFile:iconPath] autorelease];
	if (icon) {
		return icon;
	}
	[downloadQueue addObject:appID];
	[self dequeueDownload];
	return [UIImage imageNamed:@"GenericApp.png"];
}

- (void)dequeueDownload
{
	if ([downloadQueue count] == 0 || isDownloading) return;
	
	NSString *nextAppID = [[[downloadQueue objectAtIndex:0] copy] autorelease];
	[downloadQueue removeObjectAtIndex:0];
	
	dispatch_async(queue, ^ {
        BOOL downloaded = NO;
        NSString *appURL = [NSString stringWithFormat:@"https://itunes.apple.com/us/app/id%@", nextAppID];
        NSString *string = [NSString stringWithContentsOfURL:[[NSURL alloc] initWithString:appURL] encoding:NSUTF8StringEncoding error:nil];
        
        if (string != nil) {
            NSRegularExpressionOptions regexOptions = 0;
            NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:@"http:\\/\\/is[0-9]\\.mzstatic\\.com\\/image\\/thumb\\/([a-zA-Z0-9\\/\\.-]+)\\/source\\/1024x1024sr.jpg" options:regexOptions error:nil];
            
            NSTextCheckingResult *match = [regex firstMatchInString:string
                                                            options:0
                                                              range:NSMakeRange(0, [string length])];
            if (match) {
                if (match.numberOfRanges > 0) {
                    NSRange subMatchRange = [match rangeAtIndex:1];
                    
                    NSString *iconURLString;
                    
                    if ([string rangeOfString:@"\"Mac App Store\""].location != NSNotFound) {
                        iconURLString = [NSString stringWithFormat:@"http://a1.mzstatic.com/us/r30/%@/icon128.png", [string substringWithRange:subMatchRange]];
                    } else {
                        iconURLString = [NSString stringWithFormat:@"http://a1.mzstatic.com/us/r30/%@/icon75x75.png", [string substringWithRange:subMatchRange]];
                    }

                    NSURL *iconURL = [NSURL URLWithString:iconURLString];
                    
                    NSData *iconData = [NSData dataWithContentsOfURL:iconURL];
                    if (iconData != nil) {
                        UIImage *icon = [UIImage imageWithData:iconData];
                        if (icon != nil) {
                            downloaded = YES;
                            //Download was successful, write icon to file
                            NSString *iconPath = [[self iconDirectory] stringByAppendingPathComponent:nextAppID];
                            [iconData writeToFile:iconPath atomically:YES];
                            [iconCache setObject:icon forKey:nextAppID];
                            [[NSNotificationCenter defaultCenter] postNotificationName:IconManagerDownloadedIconNotification object:self userInfo:[NSDictionary dictionaryWithObject:nextAppID forKey:kIconManagerDownloadedIconNotificationAppID]];
                        }
                    }
                }
            }
        }
        
        if (downloaded == NO) {
			dispatch_async(dispatch_get_main_queue(), ^ {
				//There was a response, but the download was not successful, write the default icon, so that we won't try again and again...
				NSString *defaultIconPath = [[NSBundle mainBundle] pathForResource:@"GenericApp" ofType:@"png"];
				NSString *iconPath = [[self iconDirectory] stringByAppendingPathComponent:nextAppID];
				[[NSFileManager defaultManager] copyItemAtPath:defaultIconPath toPath:iconPath error:NULL];
			});
        }
        
		dispatch_async(dispatch_get_main_queue(), ^ {
			isDownloading = NO;
			[self dequeueDownload];
		});
	});
}

- (void)dealloc
{
	dispatch_release(queue);
	[iconCache release];
	[super dealloc];
}

@end
