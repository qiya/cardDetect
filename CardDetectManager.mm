//
//  CardDetectManager.m
//  HHMobileOfficeIOS
//
//  Created by zhengqiwen on 15/11/16.
//  Copyright © 2015年 admin. All rights reserved.
//

#import "CardDetectManager.h"
#import "MessageController.h"
#import "SVProgressHUD.h"

#import "opencv2/opencv.hpp"
#import <QuartzCore/QuartzCore.h>
#import <TesseractOCR/Tesseract.h>
#import "environ.h"
#import "CheckCardInfoController.h"
#import "SVProgressHUD.h"
#import "MBProgressHUD.h"
#import "base64.h"
#import "GTMBase64.h"
#import "JSON.h"
#import "HTTPTool.h"
#import "vendorMacro.h"
#import "MessageController.h"
using namespace cv;
using namespace std;

IplImage *RoIImg;
int currentvalue = 9;
cv::vector<cv::Mat> images;
cv::vector<int> labels;
cv::Ptr<cv::FaceRecognizer> model;

@implementation CardDetectManager
{
    UIImagePickerController *_pickerVC;
    MessageController *_msgVC;
    UIImage *_cardImg;//获取到的图片
    
    CheckCardInfoController *_checkCardVC;//名片信息保存界面
    
    
    MBProgressHUD *_stateHud;
    NSString *detectStr;
    int netDetectIndex;
    int netDetectReqIndex;
    
    CardInfoModel *_cardMod;//
    
}

- (void) beginTakePhoto:(MessageController *)presentVC//开始拍照
{
    _msgVC = presentVC;
    if(!_pickerVC)
    {
        _pickerVC = [[UIImagePickerController alloc] init];
        _pickerVC.sourceType = UIImagePickerControllerSourceTypeCamera;
        _pickerVC.mediaTypes = [UIImagePickerController availableMediaTypesForSourceType: UIImagePickerControllerSourceTypeCamera];

        _pickerVC.allowsEditing = NO;
        _pickerVC.delegate = self;
    }
 //   [_msgVC.navigationController pushViewController:_pickerVC animated:YES completion:nil];
   // [_msgVC.navigationController pushViewController:_pickerVC animated:YES];
    [_msgVC presentViewController:_pickerVC animated:YES completion:nil];
    
}



#pragma mark - UIImagePickerControllerDelegate methods
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    if(picker.sourceType == UIImagePickerControllerSourceTypeCamera)
    {
        _cardImg = [info objectForKey:UIImagePickerControllerOriginalImage];
    }
    else
    {
        NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
        if (CFStringCompare ((CFStringRef) mediaType, kUTTypeImage, 0) == kCFCompareEqualTo)
        {
            _cardImg = (UIImage *) [info objectForKey:UIImagePickerControllerOriginalImage];
        }
    }
    UIImageOrientation imageOrientation=_cardImg.imageOrientation;
    if(imageOrientation!=UIImageOrientationUp)
    {
        // 原始图片可以根据照相时的角度来显示，但UIImage无法判定，于是出现获取的图片会向左转９０度的现象。
        // 以下为调整图片角度的部分
        UIGraphicsBeginImageContext(_cardImg.size);
        [_cardImg drawInRect:CGRectMake(0, 0, _cardImg.size.width, _cardImg.size.height)];
        _cardImg = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        // 调整图片角度完毕
    }
    netDetectIndex = 0;
    netDetectReqIndex = 0;
    _checkCardVC = [[CheckCardInfoController alloc]init];
     [NSThread detachNewThreadSelector:@selector(opencvFaceDetect) toTarget:self withObject:nil];
 
}

- (UIImage *)fixOrientation:(UIImage *)aImage {
    
    // No-op if the orientation is already correct
    if (aImage.imageOrientation == UIImageOrientationUp)
        return aImage;
    
    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (aImage.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, aImage.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, aImage.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        default:
            break;
    }
    
    switch (aImage.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        default:
            break;
    }
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, aImage.size.width, aImage.size.height,
                                             CGImageGetBitsPerComponent(aImage.CGImage), 0,
                                             CGImageGetColorSpace(aImage.CGImage),
                                             CGImageGetBitmapInfo(aImage.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (aImage.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,aImage.size.height,aImage.size.width), aImage.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,aImage.size.width,aImage.size.height), aImage.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark opencv Iplimage uiimage 转换
// NOTE you SHOULD cvReleaseImage() for the return value when end of the code.
- (IplImage *)CreateIplImageFromUIImage:(UIImage *)image {
    CGImageRef imageRef = image.CGImage;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    IplImage *iplimage = cvCreateImage(cvSize(image.size.width, image.size.height), IPL_DEPTH_8U, 4);
    CGContextRef contextRef = CGBitmapContextCreate(iplimage->imageData, iplimage->width, iplimage->height,
                                                    iplimage->depth, iplimage->widthStep,
                                                    colorSpace, kCGImageAlphaPremultipliedLast|kCGBitmapByteOrderDefault);
    CGContextDrawImage(contextRef, CGRectMake(0, 0, image.size.width, image.size.height), imageRef);
    CGContextRelease(contextRef);
    CGColorSpaceRelease(colorSpace);
    
    IplImage *ret = cvCreateImage(cvGetSize(iplimage), IPL_DEPTH_8U, 3);
    cvCvtColor(iplimage, ret, CV_RGBA2BGR);
    cvReleaseImage(&iplimage);
    
    return ret;
}

// 把IplImage类型转换成UIImage类型.
// NOTE You should convert color mode as RGB before passing to this function.
- (UIImage *)convertToUIImage:(IplImage *)image {
    NSLog(@"IplImage (%d, %d) %d bits by %d channels, %d bytes/row %s",
          image->width,
          image->height,
          image->depth,
          image->nChannels,
          image->widthStep,
          image->channelSeq);
    cvCvtColor(image, image, CV_BGR2RGB);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSData *data = [NSData dataWithBytes:image->imageData length:image->imageSize];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGImageRef imageRef = CGImageCreate(image->width,
                                        image->height,
                                        image->depth,
                                        image->depth * image->nChannels,
                                        image->widthStep,
                                        colorSpace,
                                        kCGImageAlphaNone |
                                        kCGBitmapByteOrderDefault,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    
    UIImage *ret = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return ret;
}

// NOTE You should convert color mode as RGB before passing to this function
- (UIImage *)UIImageFromIplImage:(IplImage *)image {
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSData *data = [NSData dataWithBytes:image->imageData length:image->imageSize];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGImageRef imageRef = CGImageCreate(image->width, image->height,
                                        image->depth, image->depth * image->nChannels, image->widthStep,
                                        colorSpace, kCGImageAlphaNone|kCGBitmapByteOrderDefault,
                                        provider, NULL, false, kCGRenderingIntentDefault);
    UIImage *ret = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    return ret;
}

-(NSString *)processOCR:(UIImage *)image withLanguage:(NSString *)languageStr
{
    Tesseract* tesseract = [[Tesseract alloc] initWithLanguage:languageStr];
    tesseract.delegate = self;
    if([languageStr isEqualToString:@"eng"])
        [tesseract setVariableValue:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@_.(),-&/" forKey:@"tessedit_char_whitelist"];
    [tesseract setImage:image]; //image to check
    [tesseract recognize];
    return [tesseract recognizedText];
    tesseract = nil; //deallocate and free all memory
}

#pragma mark 名片信息转换
- (void)getEngWordDetect:(IplImage *)binaryImg
{
    // IplImage* grayImagePlus = cvCreateImage(cvGetSize(binaryImg), IPL_DEPTH_8U, 3);
    // cvCvtColor(binaryImg, grayImagePlus, CV_GRAY2BGR);//此处将灰度格式图像转换成BGR格式的图像
    UIImage *engBinImg = [self UIImageFromIplImage:binaryImg];
    NSString *detectNumStr =  [self processOCR:engBinImg withLanguage:@"eng"];
    [self detectNumber:detectNumStr];
}

//提交扫描图片
- (void)putScanCardImg
{
    _cardMod.cardNorImage = _cardImg;
}

//识别中文单位公司名称
- (void)detectChiUnitName:(NSString *)cardSubstr
{
    NSMutableArray *unitNameArr = @[@"公司",@"集团",
                                    @"有限"];
    for(int unitIndex = 0;unitIndex < [unitNameArr count];unitIndex++)
    {
        if([cardSubstr containsString:[unitNameArr objectAtIndex:unitIndex]])
        {
            NSLog(@"公司名称是%@",cardSubstr);
            _cardMod.cardUnitName = [NSString stringWithFormat:@"%@%@ ",_cardMod.cardUnitName,cardSubstr];
        }
        break;
    }
}

- (void)detectCustomerType
{
    _cardMod.cardLinkerType = [NSString stringWithFormat:@"%d",eCardLinkerTypeCustomer];//客户
}

//部门
- (void)detectDepatName:(NSString *)cardSubStr
{
    NSMutableArray *departNameArr = @[@"部"];
    for(int unitIndex = 0;unitIndex < [departNameArr count];unitIndex++)
    {
        if([cardSubStr containsString:[departNameArr objectAtIndex:unitIndex]])
        {
            NSLog(@"公司部门是%@",cardSubStr);
            _cardMod.cardDepart = [NSString stringWithFormat:@"%@%@ ",_cardMod.cardDepart,cardSubStr];
        }
        break;
    }
    
}

//识别中文行业职位
- (void)detectChiPositionName:(NSString *)cardSubstr
{
    NSArray *positionNameArr = @[@"顾问",@"经理",@"总监",@"代表",@"会计"];
    for(NSString *positionStr in positionNameArr)
    {
        if([cardSubstr containsString:positionStr])
        {
            NSLog(@"职位是%@",cardSubstr);
            _cardMod.cardPosition = [NSString stringWithFormat:@"%@%@ ", _cardMod.cardPosition,cardSubstr];
        }
    }
}

//识别中文名称
- (void)detectChiName:(NSString *)cardSubStr
{
    //百家姓
    NSString *nameDetectStr = @"赵钱孙李周吴郑王冯陈楮卫蒋沈韩杨朱秦尤许何吕施张孔曹严华金魏陶姜戚谢邹喻柏窦云苏潘葛奚范彭郎鲁韦昌马苗凤花方俞任袁柳酆鲍史唐费廉岑薛雷贺倪汤滕殷罗毕郝邬安常乐于时傅皮卞齐康伍余元卜顾黄和穆萧尹姚邵湛汪祁毛禹狄米贝明臧计伏成戴谈宋茅庞熊纪舒屈项祝董梁杜阮蓝闽席季麻强贾路娄危江童颜郭梅盛林刁锺徐丘骆高夏蔡田樊胡凌霍虞万支柯昝管卢莫经房裘缪干解应宗丁宣贲邓郁单杭洪包诸左石崔吉钮龚程嵇邢滑裴陆荣翁荀羊於惠甄麹家封芮羿储靳汲邴糜松井段富巫乌焦巴弓牧隗山谷车侯宓蓬全郗班仰秋仲伊宫宁仇栾暴甘斜厉戎祖武符刘景詹束龙叶幸司韶郜黎蓟薄印宿白怀蒲邰从鄂索咸籍赖卓蔺屠蒙池乔阴郁胥能苍双闻莘党翟谭贡劳逄姬申扶堵冉宰郦雍郤璩桑桂濮牛寿通边扈燕冀郏浦尚农温别庄晏柴瞿阎充慕连茹习宦艾鱼容向古易慎戈廖庾终暨居衡步都耿满弘匡国文寇广禄阙东欧殳沃利蔚越夔隆师巩厍聂晁勾敖融冷訾辛阚那简饶空曾毋沙乜养鞠须丰巢关蒯相查后荆红游竺权逑盖益桓公万俟司马上官欧阳夏侯诸葛闻人东方赫连皇甫尉迟公羊澹台公冶宗政濮阳淳于单于太叔申屠公孙仲孙轩辕令狐锺离宇文长孙慕容鲜于闾丘司徒司空丌官司寇仉督子车颛孙端木巫马公西漆雕乐正壤驷公良拓拔夹谷宰父谷梁晋楚阎法汝鄢涂钦段干百里东郭南门呼延归海羊舌微生岳帅缑亢况后有琴梁丘左丘东门西门商牟佘佴伯赏南宫墨哈谯笪年爱阳佟";
    NSString *nameSwapStr = @"";
    if([cardSubStr length] >= 2 && [cardSubStr length] <=4 )
    {
        if([nameDetectStr containsString:[cardSubStr substringWithRange:NSMakeRange(0, 1)]])//包含在百家姓里面
        {
            NSLog(@"姓名为%@",cardSubStr);
            _cardMod.cardName = [NSString stringWithFormat:@"%@%@ ",_cardMod.cardName,cardSubStr];
        }
    }
    
}

//识别中文地址
- (void)detectChiAddr:(NSString *)cardSubstr
{
    NSMutableArray *matchArr = @[@"省",@"市",@"镇",@"区",@"路",@"号",@"夏",@"室",@"室",@"楼",@"东",@"南",@"西",@"北"];
    int matchCount = 0;
    for(NSString *matchStr in matchArr)
    {
        NSPredicate* chiAddrPred = [NSPredicate predicateWithFormat:@"SELF CONTAINS %@", matchStr];
        if([chiAddrPred evaluateWithObject:cardSubstr])
            matchCount ++;
    }
    if(matchCount >= 2)
    {
        NSLog(@"地址是%@",cardSubstr);
        _cardMod.cardUnitAddr =[NSString stringWithFormat:@"%@%@ ",_cardMod.cardUnitAddr,cardSubstr] ;
    }
}

//识别数字和字母
- (void) detectNumber:(NSString *)cardStr
{
    NSError *error;
    NSString *emailRegStr = @"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,4}";
    NSString *mobileRegStr = @"1[0-9]{10}";
    NSString *telRegStr = @"[0-9]{3,4}-[0-9]{6,8}";
    NSString *faxRegStr = @"[0-9]{3,4}-[0-9]{6,8}";
    NSString *mailRegStr = @"[1-9]\d{5}(?!\d)";//邮编
    NSString *websiteRegStr = @"((http[s]{0,1}|ftp)://[a-zA-Z0-9\\.\\-]+\\.([a-zA-Z]{2,4})(:\\d+)?(/[a-zA-Z0-9\\.\\-~!@#$%^&*+?:_/=<>]*)?)|(www.[a-zA-Z0-9\\.\\-]+\\.([a-zA-Z]{2,4})(:\\d+)?(/[a-zA-Z0-9\\.\\-~!@#$%^&*+?:_/=<>]*)?)";
    NSString *QQRegStr = @"[1-9][0-9]{8,9}";
    NSArray *allItemArr = @[@"邮箱",@"手机号码",@"电话号码",@"网站",@"QQ",@"传真",@"邮编"];
    NSMutableArray *allRegStrArr = [NSMutableArray arrayWithObjects:emailRegStr,mobileRegStr,telRegStr,websiteRegStr,QQRegStr,faxRegStr,mailRegStr,nil];
    for(int itemIndex = 0;itemIndex < [allItemArr count];itemIndex++)
    {
        NSRegularExpression *numRegex = [NSRegularExpression regularExpressionWithPattern:[allRegStrArr objectAtIndex:itemIndex]
                                                                                  options:NSRegularExpressionCaseInsensitive
                                                                                    error:&error];
        NSArray *arrayOfAllMatches = [numRegex matchesInString:cardStr options:0 range:NSMakeRange(0, [cardStr length])];
        NSString *substringForMatch = @"";
        for (NSTextCheckingResult *match in arrayOfAllMatches)
        {
            NSString *matchStr = [[cardStr substringWithRange:match.range] stringByReplacingOccurrencesOfString:@" " withString:@""];
            substringForMatch = [NSString stringWithFormat:@"%@%@ ",substringForMatch,matchStr];
        }
        NSLog(@"匹配到的%@是%@",[allItemArr objectAtIndex:itemIndex],substringForMatch);
        substringForMatch = [self removeUselessWord:substringForMatch];
        if(![substringForMatch length])
        {
            continue;
        }
        switch (itemIndex)
        {
            case 0:
                _cardMod.cardEmail = [NSString stringWithFormat:@"%@%@  ",_cardMod.cardEmail,substringForMatch];
                break;
            case 1:
                _cardMod.cardMobile = [NSString stringWithFormat:@"%@%@  ",_cardMod.cardMobile,substringForMatch];;
                break;
            case 2:
                _cardMod.cardTel = [NSString stringWithFormat:@"%@%@  ",_cardMod.cardTel,substringForMatch];;
                break;
            case 3:
                _cardMod.cardWebsite = [NSString stringWithFormat:@"%@%@  ",_cardMod.cardWebsite,substringForMatch];
                break;
            case 4:
                _cardMod.cardQQ = [NSString stringWithFormat:@"%@%@  ",_cardMod.cardQQ,substringForMatch];;
                break;
            case 5:
                _cardMod.cardFax = [NSString stringWithFormat:@"%@%@  ",_cardMod.cardFax,substringForMatch];;
                break;
            case 6:
                // _checkCardVC.cardFax = [NSString stringWithFormat:@"%@  %@",_checkCardVC.cardFax,substringForMatch];;
                break;
            default:
                break;
        }
    
    }
}

//移除字符串不需要的字符
- (NSString *)removeUselessWord:(NSString *)srcStr
{
    NSString *dstStr = srcStr;
    if(dstStr)
    {
        dstStr = [dstStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];  //去除掉首尾的空白字符和换行字符
        dstStr = [dstStr stringByReplacingOccurrencesOfString:@" " withString:@""];
        dstStr = [dstStr stringByReplacingOccurrencesOfString:@"/r" withString:@""];
        dstStr = [dstStr stringByReplacingOccurrencesOfString:@"/n" withString:@""];
    }
    return dstStr;
}


#pragma mark 图片处理优化
void ImageBinarization(IplImage *src)
{	/*对灰度图像二值化，自适应门限threshold*/
    int i,j,width,height,step,chanel,threshold;
    /*size是图像尺寸，svg是灰度直方图均值，va是方差*/
    float size,avg,va,maxVa,p,a,s;
    unsigned char *dataSrc;
    float histogram[256];
    
    width = src->width;
    height = src->height;
    dataSrc = (unsigned char *)src->imageData;
    step = src->widthStep/sizeof(char);
    chanel = src->nChannels;
    /*计算直方图并归一化histogram*/
    for(i=0; i<256; i++)
        histogram[i] = 0;
    for(i=0; i<height; i++)
        for(j=0; j<width*chanel; j++)
        {
            histogram[dataSrc[i*step+j]-'0'+48]++;
        }
    size = width * height;
    for(i=0; i<256; i++)
        histogram[i] /=size;
    /*计算灰度直方图中值和方差*/
    avg = 0;
    for(i=0; i<256; i++)
        avg += i*histogram[i];
    va = 0;
    for(i=0; i<256; i++)
        va += fabs(i*i*histogram[i]-avg*avg);
    /*利用加权最大方差求门限*/
    threshold = 20;
    maxVa = 0;
    p = a = s = 0;
    for(i=0; i<256; i++)
    {
        p += histogram[i];
        a += i*histogram[i];
        s = (avg*p-a)*(avg*p-a)/p/(1-p);
        if(s > maxVa)
        {
            threshold = i;
            maxVa = s;
        }
    }
    /*二值化*/
    for(i=0; i<height; i++)
        for(j=0; j<width*chanel; j++)
        {
            if(dataSrc[i*step+j] > threshold)
                dataSrc[i*step+j] = 255;
            else
                dataSrc[i*step+j] = 0;
        }
}

- (void )setImgBlackEdge:(IplImage *)norImg
{
    int imgHeight = norImg->height;
    int imgWidth = norImg->width;
    for(int i = 0;i < imgHeight;i++)
    {
        for(int j = 0;j < 11;j++)
        {
            //获得像素的RGB值并显示, 注意内存中存储顺序是BGR
            Scalar pixel = cvGet2D(norImg, i, j);
            pixel.val[0] = 255;
            pixel.val[1] = 255;
            pixel.val[2] = 255;
            cvSet2D(norImg, i, j, pixel);
        }
    }
    for(int i = 0;i < imgHeight;i++)
    {
        for(int j = imgWidth-11;j < imgWidth;j++)
        {
            //获得像素的RGB值并显示, 注意内存中存储顺序是BGR
            Scalar pixel = cvGet2D(norImg, i, j);
            pixel.val[0] = 255;
            pixel.val[1] = 255;
            pixel.val[2] = 255;
            cvSet2D(norImg, i, j, pixel);
        }
    }
}


int ImageStretchByHistogram(IplImage *src1,IplImage *dst1)
/*************************************************
 Function:      通过直方图变换进行图像增强，将图像灰度的域值拉伸到0-255
 src1:               单通道灰度图像
 dst1:              同样大小的单通道灰度图像
 *************************************************/
{
    assert(src1->width==dst1->width);
    double p[256],p1[256],num[256];
    
    memset(p,0,sizeof(p));
    memset(p1,0,sizeof(p1));
    memset(num,0,sizeof(num));
    int height=src1->height;
    int width=src1->width;
    long wMulh = height * width;
    
    //statistics
    for(int x=0;x<src1->width;x++)
    {
        for(int y=0;y<src1-> height;y++){
            uchar v=((uchar*)(src1->imageData + src1->widthStep*y))[x];
            num[v]++;
        }
    }
    //calculate probability
    for(int i=0;i<256;i++)
    {
        p[i]=num[i]/wMulh;
    }
    
    //p1[i]=sum(p[j]);	j<=i;
    for(int i=0;i<256;i++)
    {
        for(int k=0;k<=i;k++)
            p1[i]+=p[k];
    }
    
    // histogram transformation
    for(int x=0;x<src1->width;x++)
    {
        for(int y=0;y<src1-> height;y++){
            uchar v=((uchar*)(src1->imageData + src1->widthStep*y))[x];
            ((uchar*)(dst1->imageData + dst1->widthStep*y))[x]= p1[v]*255+0.5;
        }
    }
    return 0;
}

void sharpenImage(const Mat& img, Mat& result)
{
    result.create(img.size(), img.type());
    //处理边界内部的像素点, 图像最外围的像素点应该额外处理
    for (int row = 1; row < img.rows-1; row++)
    {
        //前一行像素点
        const uchar* previous = img.ptr<const uchar>(row-1);
        //待处理的当前行
        const uchar* current = img.ptr<const uchar>(row);
        //下一行
        const uchar* next = img.ptr<const uchar>(row+1);
        uchar *output = result.ptr<uchar>(row);
        int ch = img.channels();
        int starts = ch;
        int ends = (img.cols - 1) * ch;
        for (int col = starts; col < ends; col++)
        {
            //输出图像的遍历指针与当前行的指针同步递增, 以每行的每一个像素点的每一个通道值为一个递增量, 因为要考虑到图像的通道数
            *output++ = saturate_cast<uchar>(5 * current[col] - current[col-ch] - current[col+ch] - previous[col] - next[col]);
        }
    } //end loop
    //处理边界, 外围像素点设为 0
    result.row(0).setTo(Scalar::all(0));
    result.row(result.rows-1).setTo(Scalar::all(0));
    result.col(0).setTo(Scalar::all(0));
    result.col(result.cols-1).setTo(Scalar::all(0));
}


- (void) opencvFaceDetect{
    
    if(!_cardMod)
    {
        _cardMod = [CardInfoModel new];
    }
    [_cardMod clearCardInfoData];//清空所有数据
    dispatch_async(dispatch_get_main_queue(),^{
        [SVProgressHUD showWithStatus:@"正在识别"];
    });
    UIImage* img = [_cardImg copy];
    if(img) {
        cvSetErrMode(CV_ErrModeParent);
        IplImage *image = [self CreateIplImageFromUIImage:img];
        
        IplImage *grayImg = cvCreateImage(cvSize(image->width,image->height), IPL_DEPTH_8U, 1); //先转为灰度图
        cvCvtColor(image, grayImg, CV_BGR2GRAY);
        Mat shapenSour = Mat(grayImg);//图像锐化
        Mat shapenDst;
        sharpenImage(shapenSour, shapenDst);
        IplImage imageShapenDst = IplImage(shapenDst);
        
        IplImage *dstImage = grayImg;
        ImageStretchByHistogram(grayImg, dstImage);//灰度图像增强
        
        //膨胀处理
        IplConvKernel* ker =  cvCreateStructuringElementEx(50, 2, 0, 0, 1);
        cvErode(dstImage,dstImage,ker,2);
        
        //二值化处理
        IplImage *g_pBinaryImage = cvCreateImage(cvGetSize(dstImage), IPL_DEPTH_8U, 1);
        cvThreshold(dstImage, g_pBinaryImage, 30, 255, CV_THRESH_BINARY);
        
        //获取名片信息
        [self managerCardImg:g_pBinaryImage nor3dImg:image];
        cvReleaseImage(&grayImg);
        cvReleaseImage(&image);
    }
    
}

#pragma mark 网络识别请求
-(void)getPhotoChineseString:(UIImage *)image{
    
    NSData *data=UIImageJPEGRepresentation(image, 1);
    float dataLen = [data length];
    if(dataLen > 300*1024)//不能超过300K
    {
        float reduceRate = (300*1024.f)/dataLen;
        data = UIImageJPEGRepresentation(image, reduceRate);
    }
    NSString *base64Encoded1 = [data base64EncodedStringWithOptions:0];
    //去除base64字符串编码里的特殊符号.
    NSString *baseString = (__bridge NSString *) CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                                         (CFStringRef)base64Encoded1,
                                                                                         NULL,
                                                                                         CFSTR(":/?#[]@!$&’()*+,;="),
                                                                                         kCFStringEncodingUTF8);
    
    [self sendPost:baseString];
    
}

//Unicode转化为汉字:
- (NSString *)replaceUnicode:(NSString *)unicodeStr {
    
    NSString *tempStr1 = [unicodeStr stringByReplacingOccurrencesOfString:@"\\u" withString:@"\\U"];
    NSString *tempStr2 = [tempStr1 stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *tempStr3 = [[@" \"" stringByAppendingString:tempStr2]stringByAppendingString:@"\""];
    NSData *tempData = [tempStr3 dataUsingEncoding:NSUTF8StringEncoding];
    NSString* returnStr = [NSPropertyListSerialization propertyListFromData:tempData
                                                           mutabilityOption:NSPropertyListImmutable
                                                                     format:NULL
                                                           errorDescription:NULL];
    
    return [returnStr stringByReplacingOccurrencesOfString:@"\\r\\n" withString:@"\n"];
}

-(void)sendPost:(NSString *)imageString{
    
    NSString *httpUrl = @"http://apis.baidu.com/apistore/idlocr/ocr";
    NSString *httpArg =[NSString stringWithFormat:@"fromdevice=iPhone&clientip=10.10.10.0&detecttype=LocateRecognize&languagetype=CHN_ENG&imagetype=1&image=%@",imageString];
    [self request: httpUrl withHttpArg: httpArg];
    
}

-(void)request: (NSString*)httpUrl withHttpArg: (NSString*)HttpArg  {
    
    NSURL *url = [NSURL URLWithString: httpUrl];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL: url cachePolicy: NSURLRequestUseProtocolCachePolicy timeoutInterval: 20];
    [request setHTTPMethod: @"POST"];
    [request addValue:@"edcfbc2b5d7c065c058e0d653b23088b" forHTTPHeaderField: @"apikey"];
    [request addValue:@"application/x-www-form-urlencoded" forHTTPHeaderField: @"Content-Type"];
    NSData *data = [HttpArg dataUsingEncoding: NSUTF8StringEncoding];
    [request setHTTPBody: data];
    WS(weakself)
    [NSURLConnection sendAsynchronousRequest: request
                                       queue: [NSOperationQueue mainQueue]
                           completionHandler: ^(NSURLResponse *response, NSData *data, NSError *error){
                               
                            netDetectReqIndex ++;
                            [self detectCustomerType];//客户类型
                            [self putScanCardImg];//提交扫描图片
                            _checkCardVC.isFromMessageModel = _isFromMessageModel;
                               if (error) {
                                   NSLog(@"Httperror: %@%ld", error.localizedDescription, error.code);
                                   if(netDetectReqIndex == netDetectIndex)
                                   {
                                         [SVProgressHUD showSuccessWithStatus:@"识别完成"];
                                       [_pickerVC dismissViewControllerAnimated:NO completion:^{
                                           
                                           _checkCardVC.hidesBottomBarWhenPushed = YES;
                                           [_checkCardVC setCardInfoData:_cardMod isReUploadFlag:NO];
                                           [_msgVC.navigationController pushViewController:_checkCardVC  animated:YES];
                                       }];
                                   }
                               } else {
                                   NSInteger responseCode = [(NSHTTPURLResponse *)response statusCode];
                                   NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                   NSLog(@"HttpResponseCode:%ld", responseCode);
                                   NSString *hanzi  = [self replaceUnicode:responseString];
                                   NSLog(@"HttpResponseBody %@",hanzi);
                                   if([self isDetectWrong:hanzi])//识别失败
                                   {
                                       if(netDetectReqIndex == netDetectIndex)
                                       {
                                           [SVProgressHUD showSuccessWithStatus:@"识别完成"];
                                           [_pickerVC dismissViewControllerAnimated:NO completion:^{
                                               
                                               _checkCardVC.hidesBottomBarWhenPushed = YES;
                                               [_checkCardVC setCardInfoData:_cardMod isReUploadFlag:NO];
                                               [_msgVC.navigationController pushViewController:_checkCardVC  animated:YES];
                                           }];
                                       }
                                       
                                   }
                                   else
                                   {
                                       NSArray *dataArr = [[hanzi JSONValue] objectForKey:@"retData"];
                                       [self getDetectChineseWord:dataArr detectTimes:netDetectReqIndex];
                                   }
                                   
                                
                               }
                           }];
}


- (BOOL)isDetectWrong:(NSString *)hanzi
{
    NSArray *dataArr = [[hanzi JSONValue] objectForKey:@"retData"];
    if(![[[hanzi JSONValue] objectForKey:@"errNum"] isKindOfClass:[NSNumber class]] && dataArr && ![dataArr isEqual:[NSNull null]] && [dataArr count])//不是返回@“0”都为失败
    {
        NSString *errStr = [[hanzi JSONValue] objectForKey:@"errNum"];
        if([errStr isEqualToString:@"0"])
        return NO;
        else
            return YES;
    }
 
    return YES;
}

- (void)getDetectChineseWord:(NSArray *)dataArr detectTimes:(NSInteger)detectTimes
{
     if([dataArr count])
     {
         for(int i = 0;i<[dataArr count];i++)
         {
             NSString *dstStr = [self removeUselessWord:[[dataArr objectAtIndex:i]objectForKey:@"word"]];
             if([dstStr length])//如果有长度
             {
                 detectStr  = [NSString stringWithFormat:@"%@\n%@",detectStr,dstStr];
                 NSLog(@"识别到的字符串是%@",detectStr);
             }
         }
         
         if((netDetectReqIndex == netDetectIndex) && [detectStr length])
         {
             NSMutableArray *detectSubstrArr = [detectStr componentsSeparatedByString:@"\n"];
             for(NSString *subStr in detectSubstrArr)
             {
                 NSLog(@"分割名片字符串%@",subStr);
                 
                 [self detectChiAddr:subStr];//识别中文地址
                 [self detectChiName:subStr];//识别中文姓名
                 [self detectChiPositionName:subStr];//识别中文职位
                 [self detectChiUnitName:subStr];//识别中文公司名称
                 [self detectDepatName:subStr];//部门
              
             }
             if(detectTimes == netDetectIndex)
             {
                 dispatch_async(dispatch_get_main_queue(),^{
                     
                     [SVProgressHUD showSuccessWithStatus:@"识别完成"];
                     
                     [_pickerVC dismissViewControllerAnimated:NO completion:^{
                         
                         _checkCardVC.hidesBottomBarWhenPushed = YES;
                         [_checkCardVC setCardInfoData:_cardMod isReUploadFlag:NO];
                         [_msgVC.navigationController pushViewController:_checkCardVC  animated:YES];
                     }];
                 });
             }
             
         }
         
         
     }
     else
     {
       //  [SVProgressHUD showErrorWithStatus:@"识别失败"];
     }
         
}

#pragma mark 本地识别
- (void)clearDetectData
{
    netDetectReqIndex = 0;//网络识别次数
    netDetectIndex = 0;//分割图片数
}

// expandImage 二值化之后膨胀处理的图片  nor3dImg 原始rgb图片
- (void)managerCardImg:(IplImage *)expandImage nor3dImg:(IplImage *)nor3dImg
{
    CvMemStorage* storage1 = cvCreateMemStorage( 0 );
    CvSeq* contour = NULL;
    IplImage *imgTemp = cvCloneImage(expandImage);
    
    [self setImgBlackEdge:imgTemp];//设置一个空白边框
    //寻找连通域
    cvFindContours(imgTemp, storage1, &contour, sizeof(CvContour), CV_RETR_CCOMP, CV_LINK_RUNS);
    
    IplImage *result;
    IplImage * excuteImgArr[30];
    int  excuteImgWidth[30];
    int  excuteImgHeight[30];
    int  combineImgHeight = 0;
    detectStr = @"";
    [self clearDetectData];
    for( ; contour != NULL; contour = contour -> h_next)
    {
        CvRect rect = cvBoundingRect(contour);
        if(rect.width > 50*PI_W_IPHONE5 && rect.height > 20*PI_H_IPHONE5 && rect.height < 300*PI_H_IPHONE5)
        {
            //从图像orgImage中提取一块（rectInImage）子图像imgRect
            result = cvCreateImage(cvSize(rect.width, rect.height), IPL_DEPTH_8U, 3);
            cvSetImageROI(nor3dImg,rect);
            cvCopy(nor3dImg,result);
            IplImage *grayImg = cvCreateImage(cvSize(result->width,result->height), IPL_DEPTH_8U, 1); //先转为灰度图
            cvCvtColor(result, grayImg, CV_BGR2GRAY);
            
            Mat shapenSour = Mat(grayImg);//图像锐化
            Mat shapenDst;
            sharpenImage(shapenSour, shapenDst);
            IplImage imageShapenDst = IplImage(shapenDst);
            IplImage *dstImage = grayImg;
            ImageBinarization(dstImage);
            
            IplImage* grayImagePlus = cvCreateImage(cvGetSize(dstImage), IPL_DEPTH_8U, 3);
            cvCvtColor(dstImage, grayImagePlus, CV_GRAY2BGR);//此处将灰度格式图像转换成BGR格式的图像
            //获取英文数字信息
            [self getEngWordDetect:grayImagePlus];
            
            //小图的宽度保存起来
            if(netDetectIndex < 30)
            {
                excuteImgWidth[netDetectIndex] = rect.width;
                excuteImgArr[netDetectIndex] = grayImagePlus;
            }
            combineImgHeight += rect.height;//合并的大图高度
            netDetectIndex++;
            
            if(netDetectIndex > 30)
                netDetectIndex = 30;//最多不超过30张小图
        }
        
    }
    
    if(netDetectIndex == 1)//如果只分割为一张小图
    {
        IplImage *swapImg = excuteImgArr[0];
        netDetectIndex = 1;
        UIImage *detectImg = [self UIImageFromIplImage:swapImg];
        [self getPhotoChineseString:detectImg];
        return;
    }
    
    //如果分割为两张小图
    int allSmallImgNum = netDetectIndex;
    int detectTimes = 2;
    IplImage *returnImgArr[2];
    int beginIndex;
    int endIndex;
    int eachImgY = 0;
    int bigImgHeight = 0;
    netDetectIndex = 2;
    for(int detectIndex = 0;detectIndex < detectTimes;detectIndex++)
    {
        beginIndex = allSmallImgNum/detectTimes*detectIndex;
        endIndex = (allSmallImgNum/detectTimes)*(detectIndex+1);
        if(detectIndex == detectTimes-1)
            endIndex = allSmallImgNum;
        eachImgY = 0;
        bigImgHeight = 0;
        
        for(int imgIndex = beginIndex;imgIndex < endIndex;imgIndex++)
        {
            IplImage *swapImg = excuteImgArr[imgIndex];
            bigImgHeight += swapImg->height;
        }
        int bigImgWidth = getBiggestIndex(excuteImgWidth,beginIndex,endIndex);//获取大图的宽度
        IplImage *bigImgOne = cvCreateImage(cvSize(bigImgWidth,bigImgHeight), IPL_DEPTH_8U, 3); //最后要识别的大图
        for(int imgIndex = beginIndex;imgIndex < endIndex;imgIndex++)
        {
            //载入灰度图像到目标图像
            IplImage *swapImg = excuteImgArr[imgIndex];
            cvSetImageROI(bigImgOne, cvRect(0, eachImgY, swapImg->width, swapImg->height));
            cvCopy(swapImg, bigImgOne);
            cvResetImageROI(bigImgOne);
            eachImgY += swapImg->height;
        }
        returnImgArr[detectIndex] = bigImgOne;
        UIImage *detectImg = [self UIImageFromIplImage:bigImgOne];
        [self getPhotoChineseString:detectImg];
    }
  
}


int getBiggestIndex(int *sortedArr,int beginIndex,int endindex)
{
       int i,j,k,x;
       for(i = beginIndex ;i < endindex ; i++)
       {
           k=i;
           /*k用来记录每一趟比较下来后，最大数的下标值*/
           for(j=i+1 ;j < endindex ; j++)
           {
               if(sortedArr[j] > sortedArr[k])
                       k=j;
              
           }
           if(i!=k) /*如果k的值发生改变，则把i和k所指向的元素进行交换*/
           {
               x=sortedArr[i];
               sortedArr[i]=sortedArr[k];
               sortedArr[k]=x;
           }
           return sortedArr[beginIndex];//获得最大值
       }
    
    return x;
    
    
}

- (void)dealloc {
    
    
}


@end
