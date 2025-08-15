//
//  Document.m
//  BikePlanner
//
//  Created by Daniel on 15/08/2025.
//

#import "Document.h"
#import "PlannerWindowController.h"
#import "BikePlan.h"

@interface Document ()

@end

@implementation Document


- (instancetype)init {
    self = [super init];
    if (self) {
        self.plan = [[BikePlan alloc]init];
        // Add your subclass-specific initialization here.
    }
    return self;
}



- (void)makeWindowControllers
{
    PlannerWindowController *wc = [[PlannerWindowController alloc]initWithWindowNibName:[self windowNibName] owner:self] ;
    //[wc setDocument: self];
    [self addWindowController:wc];
    //[super makeWindowControllers];
}


+ (BOOL)autosavesInPlace {
    return YES;
}


- (NSString *)windowNibName
{
    // Override returning the nib file name of the document
    // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
    return @"Document";
}


- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    if (!_plan) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileWriteUnknownError
                                        userInfo:@{ NSLocalizedDescriptionKey :
                                                        @"Document has no plan to save." }];
        }
        return nil;
    }
    
    // Archiving with NSSecureCoding
    NSData *data = nil;
    @try {
        data = [NSKeyedArchiver archivedDataWithRootObject:_plan
                                     requiringSecureCoding:YES
                                                     error:outError];
    } @catch (NSException *exception) {
        if (outError && !*outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileWriteUnknownError
                                        userInfo:@{ NSLocalizedDescriptionKey :
                                                        [NSString stringWithFormat:@"Failed to archive plan: %@", exception.reason ?: @"Unknown reason"] }];
        }
        return nil;
    }
    
    return data;

    //[NSException raise:@"UnimplementedMethod" format:@"%@ is unimplemented", NSStringFromSelector(_cmd)];
    //return nil;
}


- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    if (!data) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadCorruptFileError
                                        userInfo:@{ NSLocalizedDescriptionKey :
                                                        @"No data to read." }];
        }
        return NO;
    }
    
    id planObject = nil;
    @try {
        planObject = [NSKeyedUnarchiver unarchivedObjectOfClass:[BikePlan class]
                                                       fromData:data
                                                          error:outError];
    } @catch (NSException *exception) {
        if (outError && !*outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadCorruptFileError
                                        userInfo:@{ NSLocalizedDescriptionKey :
                                                        [NSString stringWithFormat:@"Failed to unarchive plan: %@", exception.reason ?: @"Unknown reason"] }];
        }
        return NO;
    }
    
    if (!planObject) {
        // If the unarchiver returned nil without an error, make one
        if (outError && !*outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadCorruptFileError
                                        userInfo:@{ NSLocalizedDescriptionKey :
                                                        @"Unarchived plan was nil." }];
        }
        return NO;
    }
    
    self.plan = planObject;
    return YES;
}


#pragma mark -
- (void)windowControllerDidLoadNib:(NSWindowController *)windowController
{
    [super windowControllerDidLoadNib:windowController];
}

@end
