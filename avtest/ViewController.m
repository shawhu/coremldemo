//
//  ViewController.m
//  Shooter
//
//  Created by Geppy Parziale on 2/24/12.
//  Copyright (c) 2012 iNVASIVECODE, Inc. All rights reserved.
//

#import "ViewController.h"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (strong, nonatomic) AVCaptureSession *captureSession;
@property (strong, nonatomic) AVCaptureVideoDataOutput *dataOutput;
@property (strong, nonatomic) CALayer *customPreviewLayer;
@property (weak, nonatomic) IBOutlet UILabel *myLabel;
@property (weak, nonatomic) IBOutlet UIView *previewView;

- (void)setupCameraSession;
@end


@implementation ViewController
{
    AVCaptureSession *_captureSession;
    AVCaptureVideoDataOutput *_dataOutput;
    CALayer *_customPreviewLayer;
    Resnet50 *_resnet50Model;
    MarsHabitatPricer *_marsModel;
    Resnet50Output *_predictionoutput;
}


@synthesize captureSession = _captureSession;
@synthesize dataOutput = _dataOutput;
@synthesize customPreviewLayer = _customPreviewLayer;



int _count = 0;
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // In
    size_t width = 480;
    size_t height = 480;
    size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
    Pixel_8 *baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    size_t startpos = (640-480)/2;
    const vImage_Buffer inImage = { baseAddress+startpos, height, width, bytesPerRow };
    //out
    size_t outWidth = 224;
    size_t outHeight = 224;
    size_t outbytesPerRow = 224;
    Pixel_8 *outBuffer = (Pixel_8 *)calloc(outWidth*outHeight, sizeof(Pixel_8));
    const vImage_Buffer outImage = { outBuffer, outWidth, outHeight, outbytesPerRow };
    vImageScale_Planar8(&inImage, &outImage, NULL, kvImageNoFlags);
    //or
    //[self maxFromImage:inImage toImage:outImage];
    CGColorSpaceRef grayColorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(outImage.data, outWidth, outHeight, 8, outbytesPerRow, grayColorSpace, kCGBitmapByteOrderDefault);
    
    CGImageRef dstImage = CGBitmapContextCreateImage(context);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    //update the preview layer
    dispatch_sync(dispatch_get_main_queue(), ^{
        _customPreviewLayer.contents = (__bridge id)dstImage;
    });
    
    //try to do prediction
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        //Background Thread
        _count++;
        
        if (_resnet50Model!=NULL&&_count>=30){
            _count=0;
            _predictionoutput = [_resnet50Model predictionFromImage:[self pixelBufferFromCGImageRotate90:dstImage] error:NULL];
        }
        dispatch_async(dispatch_get_main_queue(), ^(void){
            //Run UI Updates
            if (_predictionoutput!=NULL){
                _myLabel.text = _predictionoutput.classLabel;
            }
        });
    });
    //prediction end
    
    free(outBuffer);
    CGImageRelease(dstImage);
    CGContextRelease(context);
    CGColorSpaceRelease(grayColorSpace);
}



- (IBAction)StartCamera {
    [self setupCameraSession];
    [_captureSession startRunning];
}


- (void)setupCameraSession
{
    
    // Session
    _captureSession = [AVCaptureSession new];
    [_captureSession setSessionPreset:AVCaptureSessionPreset640x480];
    
    // Capture device
    AVCaptureDevice *inputDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error;
    
    // Device input
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:inputDevice error:&error];
    if ( [_captureSession canAddInput:deviceInput] )
        [_captureSession addInput:deviceInput];
    
    // Preview
    _customPreviewLayer = [CALayer layer];
    _customPreviewLayer.bounds = CGRectMake(0, 0, self.previewView.frame.size.height, self.previewView.frame.size.width);
    _customPreviewLayer.position = CGPointMake(self.previewView.frame.size.width/2., self.previewView.frame.size.height/2.);
    _customPreviewLayer.affineTransform = CGAffineTransformMakeRotation(M_PI/2);
    [self.previewView.layer addSublayer:_customPreviewLayer];
    
    _dataOutput = [AVCaptureVideoDataOutput new];
    _dataOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                                                            forKey:(NSString *)kCVPixelBufferPixelFormatTypeKey];
    
    [_dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    if ( [_captureSession canAddOutput:_dataOutput] )
        [_captureSession addOutput:_dataOutput];
    
    [_captureSession commitConfiguration];
    
    dispatch_queue_t queue = dispatch_queue_create("VideoQueue", DISPATCH_QUEUE_SERIAL);
    [_dataOutput setSampleBufferDelegate:self queue:queue];
}

- (CVPixelBufferRef) pixelBufferFromCGImageRotate90: (CGImageRef) image
{
    NSDictionary *options = @{
                              (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
                              (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                              };
    
    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(image),
                                          CGImageGetHeight(image), kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options,
                                          &pxbuffer);//kCVPixelFormatType_32ARGB
    if (status!=kCVReturnSuccess) {
        //
    }
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CGContextRef context = CGBitmapContextCreate(pxdata, width,height, 8, 4*CGImageGetWidth(image), rgbColorSpace,kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    CGContextTranslateCTM(context, 0, width);
    CGContextRotateCTM(context, -M_PI_2);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),CGImageGetHeight(image)), image);
    //testing only
    //CGImageRef newImage = CGBitmapContextCreateImage(context);
    
    //cleanup
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    return pxbuffer;
}

- (void)maxFromImage:(const vImage_Buffer)src toImage:(const vImage_Buffer)dst
{
    int kernelSize = 1;
    vImageMin_Planar8(&src, &dst, NULL, 0, 0, kernelSize, kernelSize, kvImageDoNotTile);
}

//- (CAAnimation *)animationForRotationX:(float)x Y:(float)y andZ:(float)z
//{
//    CATransform3D transform;
//    transform = CATransform3DMakeRotation(M_PI, x, y, z);
//
//    CABasicAnimation* animation;
//    animation = [CABasicAnimation animationWithKeyPath:@"transform"];
//    animation.toValue = [NSValue valueWithCATransform3D:transform];
//    animation.duration = 2;
//    animation.cumulative = YES;
//    animation.repeatCount = 10000;
//
//    return animation;
//}

// Create a UIImage from sample buffer data
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (image);
}



- (void)viewDidLoad
{
    [super viewDidLoad];
    [self StartCamera];
    _resnet50Model = [[Resnet50 alloc] init];
}

@end

