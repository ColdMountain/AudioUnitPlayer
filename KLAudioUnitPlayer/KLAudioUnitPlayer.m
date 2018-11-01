//
//  KLAudioUnitPlayer.m
//  CoolChat
//
//  Created by coldMountain on 2018/10/25.
//  Copyright © 2018 ColdMountain. All rights reserved.
//

#import "KLAudioUnitPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

@interface KLAudioUnitPlayer()
{
    AudioUnit _outAudioUinit;
    AudioBufferList *_renderBufferList;
    AudioFileStreamID _audioFileStreamID;
    AudioConverterRef _converter;
    AudioStreamBasicDescription _streamDescription;
    NSInteger _readedPacketIndex;
    UInt32 _renderBufferSize;
}
@property (nonatomic, strong) NSMutableArray<NSData*> *paketsArray;
@end

@implementation KLAudioUnitPlayer
//设置输出参数
static AudioStreamBasicDescription PCMStreamDescription()
{
    AudioStreamBasicDescription description;
    description.mSampleRate = 44100.0;
    description.mFormatID = kAudioFormatLinearPCM;
    description.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger;
    description.mFramesPerPacket = 1; //每一帧只有一个Packet
    description.mBytesPerPacket = 4;  //每个Packet只有2个byte
    description.mBytesPerFrame = 4;   //每帧只有2个byte，声道数*位深*Packet
    description.mChannelsPerFrame = 1;//声道数
    description.mBitsPerChannel = 16; //位深
    description.mReserved = 0;
    return description;
}

//读取原有数据 放到ioData

OSStatus CMAudioConverterComplexInputDataProc(AudioConverterRef  inAudioConverter,
                                              UInt32*            ioNumberDataPackets,
                                              AudioBufferList *  ioData,
                                              AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription,
                                              void * __nullable inUserData){
    KLAudioUnitPlayer *self = (__bridge KLAudioUnitPlayer *)(inUserData);
    if (self->_readedPacketIndex >= self.paketsArray.count) {
        NSLog(@"No Data");
        return 'bxmo';
    }
    NSData *packet = self.paketsArray[self->_readedPacketIndex];
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mData = (void *)packet.bytes;
    ioData->mBuffers[0].mDataByteSize = (UInt32)packet.length;
    
    static AudioStreamPacketDescription aspdesc;
    aspdesc.mDataByteSize = (UInt32)packet.length;
    aspdesc.mStartOffset = 0;
    aspdesc.mVariableFramesInPacket = 1;
    *outDataPacketDescription = &aspdesc;
    self->_readedPacketIndex++;
    return 0;
}

OSStatus  CMAURenderCallback(void *                      inRefCon,
                             AudioUnitRenderActionFlags* ioActionFlags,
                             const AudioTimeStamp*       inTimeStamp,
                             UInt32                      inBusNumber,
                             UInt32                      inNumberFrames,
                             AudioBufferList*            __nullable ioData){
    KLAudioUnitPlayer * self = (__bridge KLAudioUnitPlayer *)(inRefCon);
    @synchronized (self) {
        if (self->_readedPacketIndex < self.paketsArray.count) {
            @autoreleasepool {
                UInt32 packetSize = inNumberFrames;
                //转换格式
                OSStatus status = AudioConverterFillComplexBuffer(self->_converter,
                                                                  CMAudioConverterComplexInputDataProc,
                                                                  (__bridge void *)self,
                                                                  &packetSize,
                                                                  self->_renderBufferList,
                                                                  NULL);
                
                if (status != noErr && status != 'bxnd') {
                    [self stop];
                    return -1;
                }else if (!packetSize) {
                    ioData->mNumberBuffers = 0;
                }else {
                    ioData->mNumberBuffers = 1;
                    ioData->mBuffers[0].mNumberChannels = 2;
                    ioData->mBuffers[0].mDataByteSize = self->_renderBufferList->mBuffers[0].mDataByteSize;
                    ioData->mBuffers[0].mData =self->_renderBufferList->mBuffers[0].mData;
                    self->_renderBufferList->mBuffers[0].mDataByteSize = self->_renderBufferSize;
                }
            }
        }
        else {
            ioData->mNumberBuffers = 0;
            [self stop];
            return -1;
        }
    }
    return noErr;
}

/* 第一个参数,回调的第一个参数是Open方法中的上下文对象;
 * 第二个参数,inAudioFileStream是和Open方法中第四个返回参数AudioFileStreamID一样，表示当前FileStream的ID;
 * 第三个参数,是此次回调解析的信息ID。表示当前PropertyID对应的信息已经解析完成信息(例如数据格式、音频数据的偏移量等等),使用者可以通过AudioFileStreamGetProperty接口获取PropertyID对应的值或者数据结构;
 * 第四个参数,ioFlags是一个返回参数，表示这个property是否需要被缓存，如果需要赋值kAudioFileStreamPropertyFlag_PropertyIsCached否则不赋值
 */
void CMAudioFileStream_PropertyListenerProc(void *                        inClientData,
                                            AudioFileStreamID             inAudioFileStream,
                                            AudioFileStreamPropertyID     inPropertyID,
                                            AudioFileStreamPropertyFlags* oFlags)
{
    if (inPropertyID == kAudioFileStreamProperty_DataFormat) {
        KLAudioUnitPlayer *self = (__bridge KLAudioUnitPlayer *)(inClientData);
        UInt32 dataSize = 0;
        Boolean writable = false;
        OSStatus status = AudioFileStreamGetPropertyInfo(inAudioFileStream,
                                                         kAudioFileStreamProperty_DataFormat,
                                                         &dataSize,
                                                         &writable);
        assert(status == noErr);
        
        status = AudioFileStreamGetProperty(inAudioFileStream,
                                            kAudioFileStreamProperty_DataFormat,
                                            &dataSize,
                                            &self->_streamDescription);
        assert(status == noErr);
        AudioStreamBasicDescription destFormat = PCMStreamDescription();
        status = AudioConverterNew(&self->_streamDescription,
                                   &destFormat,
                                   &self->_converter);
        assert(status == noErr);
    }
    
}

/* 第一个参数，一如既往的上下文对象；
 * 第二个参数，本次处理的数据大小；
 * 第三个参数，本次总共处理了多少帧（即代码里的Packet）；
 * 第四个参数，本次处理的所有数据；
 * 第五个参数，AudioStreamPacketDescription数组，存储了每一帧数据是从第几个字节开始的，这一帧总共多少字节。
 */
void CMAudioFileStreamPacketsProc(void *                         inClientData,
                                  UInt32                         inNumberBytes,
                                  UInt32                         inNumberPackets,
                                  const void *                   inInputData,
                                  AudioStreamPacketDescription * inPacketDescriptions)
{
    KLAudioUnitPlayer *self = (__bridge KLAudioUnitPlayer *)(inClientData);
    for (int i = 0; i < inNumberPackets; i++) {
        SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
        UInt32 packetSize = inPacketDescriptions[i].mDataByteSize;
        assert(packetSize > 0);
        NSData *packet = [NSData dataWithBytes:inInputData + packetOffset length:packetSize];
        [self.paketsArray addObject:packet];
    }
    //    printf("readedPackIndex:%ld\n",(long)self->_readedPacketIndex);
    //    printf("packetsArray:%lu\n",(unsigned long)self.paketsArray.count);
    //    printf("packetsPerSecond:%f\n",[self packetsPerSecond]);
    //    if (
    //        self->_readedPacketIndex == 0 &&
    //        self.paketsArray.count
    //        > [self packetsPerSecond]*3
    //        ) {
    //        [self play];
    //    }
    if (self.paketsArray.count) {
        [self play];
    }
}

- (double)packetsPerSecond{
    if (_streamDescription.mFramesPerPacket) {
        //        printf("采样率:%f\n每一帧的数量:%d\n",_streamDescription.mSampleRate,_streamDescription.mFramesPerPacket);
        //        printf("packetsPerSecond:%f\n",_streamDescription.mSampleRate / _streamDescription.mFramesPerPacket);
        return _streamDescription.mSampleRate / _streamDescription.mFramesPerPacket;
    }
    return 44100.0 / 1024.0;
}

#pragma mark - 首先进行初始化操作
- (instancetype)init{
    if (self = [super init]) {
        _paketsArray = [NSMutableArray arrayWithCapacity:0];
        [self setupOutAudioUnit];
        // 创建音频文件流分析器
        /* 第一个参数和之前的AudioSession的初始化方法一样是一个上下文对象
         * 第二个参数AudioFileStream_PropertyListenerProc是歌曲信息解析的回调，每解析出一个歌曲信息都会进行一次回调
         * 第三个参数AudioFileStream_PacketsProc是分离帧的回调，每解析出一部分帧就会进行一次回调
         * 第四个参数AudioFileTypeID是文件类型的提示，这个参数来帮助AudioFileStream对文件格式进行解析
         * 第五个参数是返回的AudioFileStream实例对应的AudioFileStreamID，这个ID需要保存起来作为后续一些方法的参数使用
         */
        AudioFileStreamOpen((__bridge void * _Nullable)(self),
                            CMAudioFileStream_PropertyListenerProc,
                            CMAudioFileStreamPacketsProc,
                            0,
                            &_audioFileStreamID);
    }
    return self;
}

#pragma mark - 设置播放时的AudioUnit属性

- (void)setupOutAudioUnit{
    AudioComponentDescription outputUinitDesc;
    memset(&outputUinitDesc, 0, sizeof(AudioComponentDescription));
    outputUinitDesc.componentType = kAudioUnitType_Output;
    outputUinitDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    outputUinitDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    outputUinitDesc.componentFlags = 0;
    outputUinitDesc.componentFlagsMask = 0;
    AudioComponent outComponent = AudioComponentFindNext(NULL, &outputUinitDesc);
    OSStatus status = AudioComponentInstanceNew(outComponent, &_outAudioUinit);
    assert(status == noErr);
    
    AudioStreamBasicDescription pcmStreamDesc = PCMStreamDescription();
    AudioUnitSetProperty(_outAudioUinit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Input,
                         0,
                         &pcmStreamDesc,
                         sizeof(pcmStreamDesc));
    
    AURenderCallbackStruct callBackStruct;
    callBackStruct.inputProc = CMAURenderCallback;
    callBackStruct.inputProcRefCon = (__bridge void * _Nullable)(self);
    AudioUnitSetProperty(_outAudioUinit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Global,
                         0,
                         &callBackStruct,
                         sizeof(AURenderCallbackStruct));
    
    UInt32 bufferSize = 4096 * 4;
    _renderBufferSize = bufferSize;
    _renderBufferList = calloc(4, sizeof(UInt32)+sizeof(bufferSize));
    _renderBufferList->mNumberBuffers = 1;
    _renderBufferList->mBuffers[0].mData = calloc(1, bufferSize);
    _renderBufferList->mBuffers[0].mDataByteSize = bufferSize;
    _renderBufferList->mBuffers[0].mNumberChannels = 1;
}

#pragma mark - 传入数据

- (void)kl_playAudioWithData:(char*)pBuf andLength:(ssize_t)length timeStamp:(NSInteger)timeStamp{
    OSStatus status = AudioFileStreamParseBytes(_audioFileStreamID,
                                                (UInt32)length,
                                                pBuf,
                                                0);
    assert(status == noErr);
}

- (void)play{
    OSStatus status = AudioOutputUnitStart(_outAudioUinit);
    assert(status == noErr);
}

- (void)stop{
    OSStatus status = AudioOutputUnitStop(_outAudioUinit);
    assert(status == noErr);
}

@end
