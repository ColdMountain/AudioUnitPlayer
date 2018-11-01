//
//  KLAudioUnitPlayer.h
//  CoolChat
//
//  Created by coldMountain on 2018/10/25.
//  Copyright © 2018 ColdMountain. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KLAudioUnitPlayer : NSObject

- (instancetype)init;
- (void)kl_playAudioWithData:(char*)pBuf andLength:(ssize_t)length timeStamp:(NSInteger)timeStamp;

@end

