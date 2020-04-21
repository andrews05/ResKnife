#import "ElementFIXD.h"

#define SIZE_ON_DISK (4)

@implementation ElementFIXD
@synthesize fixedValue;

- (void)readDataFrom:(TemplateStream *)stream
{
	Fixed tmp = 0;
	[stream readAmount:SIZE_ON_DISK toBuffer:&tmp];
	fixedValue = CFSwapInt32BigToHost(tmp);
}

- (UInt32)sizeOnDisk:(UInt32)currentSize
{
	return SIZE_ON_DISK;
}

- (void)writeDataTo:(TemplateStream *)stream
{
	Fixed tmp = CFSwapInt32HostToBig(fixedValue);
	[stream writeAmount:SIZE_ON_DISK fromBuffer:&tmp];
}

- (float)value
{
	return FixedToFloat(fixedValue);
}

- (void)setValue:(float)value
{
	fixedValue = FloatToFixed(value);
}

+ (NSFormatter *)sharedFormatter
{
    static NSNumberFormatter *formatter = nil;
    if (!formatter) {
        formatter = [[NSNumberFormatter alloc] init];
        formatter.hasThousandSeparators = NO;
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.maximumFractionDigits = 6;
        formatter.minimum = @(-32768);
        formatter.maximum = @(32768);
    }
    return formatter;
}

@end
