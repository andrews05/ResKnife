#import <Foundation/Foundation.h>
#import "../Plug-Ins/ResKnifeResourceProtocol.h"

/*!
@class			Resource
@author			Nicholas Shanks
@abstract		Encapsulates a single resource and all associated meta-data.
@description	The Resource class fully complies with key-value coding, with the keys @"name", @"type", @"resID", @"attributes", @"data", @"dirty" and @"representedFork" available.
*/

@interface Resource : NSObject <NSCopying, NSCoding, ResKnifeResourceProtocol>
{
@private
	// flags
	BOOL			dirty;
	NSString		*representedFork;
	
	// resource information
	NSString		*name;
	OSType			type;
	short			resID;			// signed short
	UInt16			attributes;		// unsigned short
	
	// the actual data
	NSData			*data;
	
	// the document name for display to the user; updating this is the responsibility of the document itself
	NSString		*_docName;
}

// accessor methods not part of the protocol
@property (getter = isDirty) BOOL dirty;
@property (copy) NSString *representedFork;
- (void)_setName:(NSString *)newName;
- (void)setDocumentName:(NSString *)docName;

// init methods
- (instancetype)initWithType:(OSType)typeValue andID:(short)resIDValue;
- (instancetype)initWithType:(OSType)typeValue andID:(short)resIDValue withName:(NSString *)nameValue andAttributes:(UInt16)attributesValue;
- (instancetype)initWithType:(OSType)typeValue andID:(short)resIDValue withName:(NSString *)nameValue andAttributes:(UInt16)attributesValue data:(NSData *)dataValue;

// autoreleased resource methods
+ (instancetype)resourceOfType:(OSType)typeValue andID:(short)resIDValue;
+ (instancetype)resourceOfType:(OSType)typeValue andID:(short)resIDValue withName:(NSString *)nameValue andAttributes:(UInt16)attributesValue;
+ (instancetype)resourceOfType:(OSType)typeValue andID:(short)resIDValue withName:(NSString *)nameValue andAttributes:(UInt16)attributesValue data:(NSData *)dataValue;

+ (Resource *)getResourceOfType:(OSType)typeValue andID:(short)resIDValue inDocument:(NSDocument *)searchDoc;

@end
