//
//  SRReSign.m
//  iReSignCommand
//
//  Created by rexshi on 6/17/14.
//  Copyright (c) 2014 rexshi. All rights reserved.
//

#import "SRReSign.h"

static NSString *kKeyPrefsBundleIDChange        = @"keyBundleIDChange";

static NSString *kKeyBundleIDPlistApp           = @"CFBundleIdentifier";
static NSString *kKeyBundleIDPlistiTunesArtwork = @"softwareVersionBundleId";

static NSString *kPayloadDirName                = @"Payload";
static NSString *kInfoPlistFilename             = @"Info.plist";
static NSString *kiTunesMetadataFileName        = @"iTunesMetadata";

@implementation SRReSign

@synthesize workingPath, certName, originalIpaPath, outputIpaPath, provisioningPath, entitlementPath, unzipcPath;

- (id)init
{
    if (self = [super init]) {
        originalIpaPath = @"";
        entitlementPath = @"entitlements.plist";
        bundleIDNew = @"";
        certName = @"";
        provisioningPath = @"";
    }
    
    return self;
}

- (void)setup
{    
    defaults = [NSUserDefaults standardUserDefaults];
    
    if (!provisioningPath || [provisioningPath isEqualToString:@""]) {
        [self _logErrorWithTitle:@"Error" AndMessage:@"mobileprovisionPath do not provided."];
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:provisioningPath]) {
        [self _logErrorWithTitle:@"Can not find mobileprovision at:" AndMessage:provisioningPath];
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/zip"]) {
        [self _logErrorWithTitle:@"Error" AndMessage:@"This app cannot run without the zip utility present at /usr/bin/zip"];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:unzipcPath]) {
        [self _logErrorWithTitle:@"Error" AndMessage:@"This app cannot run without the unzipc utility present at unzipcPath"];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/codesign"]) {
        [self _logErrorWithTitle:@"Error" AndMessage:@"This app cannot run without the codesign utility present at /usr/bin/codesign"];
    }
    
    // Look up available signing certificates
    [self getCerts];

}

- (NSString *)randomString:(NSInteger)lenght
{
    NSString *all = @"abcedfghigklmnopqrstuvwxyz1234567890";
    
    NSString *result = @"";
    NSRange range;
    int random;
    NSString *word;
    for (int i = 0; i < lenght; i++) {
        random = arc4random() % 36;
        
        range.location = random;
        range.length = 1;
        word = [all substringWithRange:range];
        
        result = [result stringByAppendingString:word];
    }
    
    return result;
}

- (void)resign
{
    [self setup];

    codesigningResult = nil;
    verificationResult = nil;
    
    workingPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"com.appulize.iresign."] stringByAppendingString:[self randomString:8]];
    
    if (certName) {
        if ([[[originalIpaPath pathExtension] lowercaseString] isEqualToString:@"ipa"]) {
            [self disableControls];
            
            NSLog(@"Setting up working directory in %@",workingPath);
            [self _logStatus:@"Setting up working directory"];
            
            [[NSFileManager defaultManager] removeItemAtPath:workingPath error:nil];
            
            [[NSFileManager defaultManager] createDirectoryAtPath:workingPath withIntermediateDirectories:TRUE attributes:nil error:nil];
            
            if (originalIpaPath && [originalIpaPath length] > 0) {
                NSLog(@"Unzipping %@",originalIpaPath);
                [self _logStatus:@"Extracting original app"];
            }
            
            unzipTask = [[NSTask alloc] init];
//            [unzipTask setLaunchPath:@"/usr/bin/unzip"];
//            [unzipTask setArguments:[NSArray arrayWithObjects:@"-q", originalIpaPath, @"-d", workingPath, nil]];
            // 因为unzip在解压中文文件名时，会乱码，所以，这里用我们自己的unzipc程序去替代
            [unzipTask setLaunchPath:unzipcPath];
            [unzipTask setArguments:[NSArray arrayWithObjects:originalIpaPath, workingPath, nil]];

            [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkUnzip:) userInfo:nil repeats:TRUE];
            
            [unzipTask launch];
        } else {
            [self _logErrorWithTitle:@"Error" AndMessage:@"You must choose an *.ipa file"];
            [self enableControls];
            [self _logStatus:@"Please try again"];
        }
    } else {
        [self _logErrorWithTitle:@"Error" AndMessage:@"You must choose an signing certificate from dropdown."];
        [self enableControls];
        [self _logStatus:@"Please try again"];
    }
}

- (void)checkUnzip:(NSTimer *)timer {
    if ([unzipTask isRunning] == 0) {
        [timer invalidate];
        unzipTask = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[workingPath stringByAppendingPathComponent:@"Payload"]]) {
            NSLog(@"Unzipping done");
            [self _logStatus:@"Original app extracted"];
            
            // Do not change bundle ID
            if (NO) {
                [self doBundleIDChange:bundleIDNew];
            }
            
            if ([provisioningPath isEqualTo:@""]) {
                [self doCodeSigning];
            } else {
                [self doProvisioning];
            }
        } else {
            [self _logErrorWithTitle:@"Error" AndMessage:@"Unzip failed"];
            [self enableControls];
            [self _logStatus:@"Ready"];
        }
    }
}

- (BOOL)doBundleIDChange:(NSString *)newBundleID {
    BOOL success = YES;
    
    success &= [self doAppBundleIDChange:newBundleID];
    success &= [self doITunesMetadataBundleIDChange:newBundleID];
    
    return success;
}


- (BOOL)doITunesMetadataBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:workingPath error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"plist"]) {
            infoPlistPath = [workingPath stringByAppendingPathComponent:file];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistiTunesArtwork newBundleID:newBundleID plistOutOptions:NSPropertyListXMLFormat_v1_0];
    
}

- (BOOL)doAppBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            infoPlistPath = [[[workingPath stringByAppendingPathComponent:kPayloadDirName]
                              stringByAppendingPathComponent:file]
                             stringByAppendingPathComponent:kInfoPlistFilename];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistApp newBundleID:newBundleID plistOutOptions:NSPropertyListBinaryFormat_v1_0];
}

- (BOOL)changeBundleIDForFile:(NSString *)filePath bundleIDKey:(NSString *)bundleIDKey newBundleID:(NSString *)newBundleID plistOutOptions:(NSPropertyListWriteOptions)options {
    
    NSMutableDictionary *plist = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        plist = [[NSMutableDictionary alloc] initWithContentsOfFile:filePath];
        [plist setObject:newBundleID forKey:bundleIDKey];
        
        NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:plist format:options options:kCFPropertyListImmutable error:nil];
        
        return [xmlData writeToFile:filePath atomically:YES];
        
    }
    
    return NO;
}


- (void)doProvisioning {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:@"Payload"] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            appPath = [[workingPath stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:file];
            if ([[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                NSLog(@"Found embedded.mobileprovision, deleting.");
                [[NSFileManager defaultManager] removeItemAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] error:nil];
            }
            break;
        }
    }
    
    NSString *targetPath = [appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    
    provisioningTask = [[NSTask alloc] init];
    [provisioningTask setLaunchPath:@"/bin/cp"];
    [provisioningTask setArguments:[NSArray arrayWithObjects:provisioningPath, targetPath, nil]];
    
    [provisioningTask launch];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkProvisioning:) userInfo:nil repeats:TRUE];
}

- (void)checkProvisioning:(NSTimer *)timer {
    if ([provisioningTask isRunning] == 0) {
        [timer invalidate];
        provisioningTask = nil;
        
        NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:@"Payload"] error:nil];
        
        for (NSString *file in dirContents) {
            if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
                appPath = [[workingPath stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:file];
                if ([[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                    
                    BOOL identifierOK = FALSE;
                    NSString *identifierInProvisioning = @"";
                    
                    NSString *embeddedProvisioning = [NSString stringWithContentsOfFile:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] encoding:NSASCIIStringEncoding error:nil];
                    NSArray* embeddedProvisioningLines = [embeddedProvisioning componentsSeparatedByCharactersInSet:
                                                          [NSCharacterSet newlineCharacterSet]];
                    
                    for (int i = 0; i <= [embeddedProvisioningLines count]; i++) {
                        if ([[embeddedProvisioningLines objectAtIndex:i] rangeOfString:@"application-identifier"].location != NSNotFound) {
                            
                            NSInteger fromPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"<string>"].location + 8;
                            
                            NSInteger toPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"</string>"].location;
                            
                            NSRange range;
                            range.location = fromPosition;
                            range.length = toPosition-fromPosition;
                            
                            NSString *fullIdentifier = [[embeddedProvisioningLines objectAtIndex:i+1] substringWithRange:range];
                            
                            NSArray *identifierComponents = [fullIdentifier componentsSeparatedByString:@"."];
                            
                            if ([[identifierComponents lastObject] isEqualTo:@"*"]) {
                                identifierOK = TRUE;
                            }
                            
                            for (int i = 1; i < [identifierComponents count]; i++) {
                                identifierInProvisioning = [identifierInProvisioning stringByAppendingString:[identifierComponents objectAtIndex:i]];
                                if (i < [identifierComponents count]-1) {
                                    identifierInProvisioning = [identifierInProvisioning stringByAppendingString:@"."];
                                }
                            }
                            break;
                        }
                    }
                    
                    NSLog(@"Mobileprovision identifier: %@",identifierInProvisioning);
                    
                    NSString *infoPlist = [NSString stringWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"] encoding:NSASCIIStringEncoding error:nil];
                    if ([infoPlist rangeOfString:identifierInProvisioning].location != NSNotFound) {
                        NSLog(@"Identifiers match");
                        identifierOK = TRUE;
                    }
                    
                    // we ignore this
                    identifierOK = TRUE;
                    
                    if (!identifierOK) {
                        NSLog(@"Product identifiers don't match");
                        identifierOK = TRUE;
                    }
                    
                    if (identifierOK) {
                        NSLog(@"Provisioning completed.");
                        [self _logStatus:@"Provisioning completed"];
                        [self doCodeSigning];
                    } else {
                        [self _logErrorWithTitle:@"Error" AndMessage:@"Product identifiers don't match"];
                        [self enableControls];
                        [self _logStatus:@"Ready"];
                    }
                } else {
                    [self _logErrorWithTitle:@"Error" AndMessage:@"Provisioning failed"];
                    [self enableControls];
                    [self _logStatus:@"Ready"];
                }
                break;
            }
        }
    }
}

- (void)doCodeSigning {
    appPath = nil;
    
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[workingPath stringByAppendingPathComponent:@"Payload"] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            appPath = [[workingPath stringByAppendingPathComponent:@"Payload"] stringByAppendingPathComponent:file];
            NSLog(@"Found %@",appPath);
            appName = file;
            [self _logStatus:[NSString stringWithFormat:@"Codesigning %@",file]];
            break;
        }
    }
    
    if (appPath) {
        NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"-fs", certName, nil];
        
        NSDictionary *systemVersionDictionary = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
        NSString * systemVersion = [systemVersionDictionary objectForKey:@"ProductVersion"];
        NSArray * version = [systemVersion componentsSeparatedByString:@"."];
        if ([version[0] intValue]<10 || ([version[0] intValue]==10 && [version[1] intValue]<=9)) {
            
            /*
             Before OSX 10.9, code signing requires a version 1 signature.
             The resource envelope is necessary.
             To ensure it is added, append the resource flag to the arguments.
             */
            
            NSString *resourceRulesPath = [[NSBundle mainBundle] pathForResource:@"ResourceRules" ofType:@"plist"];
            NSString *resourceRulesArgument = [NSString stringWithFormat:@"--resource-rules=%@",resourceRulesPath];
            [arguments addObject:resourceRulesArgument];
        } else {
            
            /*
             For OSX 10.9 and later, code signing requires a version 2 signature.
             The resource envelope is obsolete.
             To ensure it is ignored, remove the resource key from the Info.plist file.
             */
            
            NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
            NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
            [infoDict removeObjectForKey:@"CFBundleResourceSpecification"];
            [infoDict writeToFile:infoPath atomically:YES];
            [arguments addObject:@"--no-strict"]; // http://stackoverflow.com/a/26204757
        }
        
        if (![entitlementPath isEqualToString:@""]) {
            [arguments addObject:[NSString stringWithFormat:@"--entitlements=%@", entitlementPath]];
        }
        
        [arguments addObjectsFromArray:[NSArray arrayWithObjects:appPath, nil]];
        
        codesignTask = [[NSTask alloc] init];
        [codesignTask setLaunchPath:@"/usr/bin/codesign"];
        [codesignTask setArguments:arguments];
		
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCodesigning:) userInfo:nil repeats:TRUE];
        
        
        NSPipe *pipe=[NSPipe pipe];
        [codesignTask setStandardOutput:pipe];
        [codesignTask setStandardError:pipe];
        NSFileHandle *handle=[pipe fileHandleForReading];
        
        [codesignTask launch];
        
        [NSThread detachNewThreadSelector:@selector(watchCodesigning:)
                                 toTarget:self withObject:handle];
    }
}

- (void)watchCodesigning:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        codesigningResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        
    }
}

- (void)checkCodesigning:(NSTimer *)timer {
    if ([codesignTask isRunning] == 0) {
        [timer invalidate];
        codesignTask = nil;
        NSLog(@"Codesigning done");
        [self _logStatus:@"Codesigning completed"];
        [self doVerifySignature];
    }
}

- (void)doVerifySignature {
    if (appPath) {
        verifyTask = [[NSTask alloc] init];
        [verifyTask setLaunchPath:@"/usr/bin/codesign"];
        [verifyTask setArguments:[NSArray arrayWithObjects:@"-v", appPath, nil]];
		
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkVerificationProcess:) userInfo:nil repeats:TRUE];
        
        NSLog(@"Verifying %@",appPath);
        [self _logStatus:[NSString stringWithFormat:@"Verifying %@",appName]];
        
        NSPipe *pipe=[NSPipe pipe];
        [verifyTask setStandardOutput:pipe];
        [verifyTask setStandardError:pipe];
        NSFileHandle *handle=[pipe fileHandleForReading];
        
        [verifyTask launch];
        
        [NSThread detachNewThreadSelector:@selector(watchVerificationProcess:)
                                 toTarget:self withObject:handle];
    }
}

- (void)watchVerificationProcess:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        verificationResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        
    }
}

- (void)checkVerificationProcess:(NSTimer *)timer {
    if ([verifyTask isRunning] == 0) {
        [timer invalidate];
        verifyTask = nil;
        if ([verificationResult length] == 0) {
            NSLog(@"Verification done");
            [self _logStatus:@"Verification completed"];
            [self doZip];
        } else {
            NSString *error = [[codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:verificationResult];
            [self _logErrorWithTitle:@"Signing failed" AndMessage:error];
            [self enableControls];
            [self _logStatus:@"Please try again"];
        }
    }
}

- (void)doZip {
    if (appPath) {
        NSLog(@"Dest: %@", outputIpaPath);
        
        zipTask = [[NSTask alloc] init];
        [zipTask setLaunchPath:@"/usr/bin/zip"];
        [zipTask setCurrentDirectoryPath:workingPath];
        [zipTask setArguments:[NSArray arrayWithObjects:@"-qry", outputIpaPath, @".", nil]];
		
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkZip:) userInfo:nil repeats:TRUE];
        
        NSLog(@"Zipping %@", outputIpaPath);
        [self _logStatus:[NSString stringWithFormat:@"Saving %@", outputIpaPath]];
        
        [zipTask launch];
    }
}

- (void)checkZip:(NSTimer *)timer {
    if ([zipTask isRunning] == 0) {
        [timer invalidate];
        zipTask = nil;
        NSLog(@"Zipping done");
        [self _logStatus:[NSString stringWithFormat:@"Saved %@",outputIpaPath]];
        
        [[NSFileManager defaultManager] removeItemAtPath:workingPath error:nil];
        
        [self enableControls];
        
        NSString *result = [[codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:verificationResult];
        NSLog(@"Codesigning result: %@",result);
        
        exit(0);
    }
}

- (void)disableControls
{
  
}

- (void)enableControls
{

}

- (void)getCerts {
    
    getCertsResult = nil;
    
    NSLog(@"Getting Certificate IDs");
    [self _logStatus:@"Getting Signing Certificate IDs"];
    
    certTask = [[NSTask alloc] init];
    [certTask setLaunchPath:@"/usr/bin/security"];
    [certTask setArguments:[NSArray arrayWithObjects:@"find-identity", @"-v", @"-p", @"codesigning", nil]];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCerts:) userInfo:nil repeats:TRUE];
    
    NSPipe *pipe=[NSPipe pipe];
    [certTask setStandardOutput:pipe];
    [certTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];
    
    [certTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchGetCerts:) toTarget:self withObject:handle];
}

- (void)watchGetCerts:(NSFileHandle*)streamHandle {
    @autoreleasepool {

        NSString *securityResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        // Verify the security result
        if (securityResult == nil || securityResult.length < 1) {
            // Nothing in the result, return
            return;
        }
        NSArray *rawResult = [securityResult componentsSeparatedByString:@"\""];
        NSMutableArray *tempGetCertsResult = [NSMutableArray arrayWithCapacity:20];
        for (int i = 0; i <= [rawResult count] - 2; i+=2) {
            
            if (rawResult.count - 1 < i + 1) {
                // Invalid array, don't add an object to that position
            } else {
                // Valid object
                [tempGetCertsResult addObject:[rawResult objectAtIndex:i+1]];
            }
        }
        
        installedCertItems = [NSMutableArray arrayWithArray:tempGetCertsResult];
        
        if ([installedCertItems indexOfObject:certName] == NSNotFound) {
            NSString *log = [NSString stringWithFormat:@"The cert is not installed on keychain: %@", certName];
            [self _logErrorWithTitle:log AndMessage:@""];
        }
    }
}

- (void)checkCerts:(NSTimer *)timer {
    
    if ([certTask isRunning] == 0) {
        [timer invalidate];
        certTask = nil;
        
        if ([installedCertItems count] > 0) {
            NSLog(@"Get Certs done");
            [self _logStatus:@"Signing Certificate IDs extracted"];
            
        } else {
            [self _logErrorWithTitle:@"Error" AndMessage:@"Getting Certificate ID's failed"];
            [self enableControls];
            [self _logStatus:@"Ready"];
        }
    }
}


#pragma mark - Alert Methods

/* NSRunAlerts are being deprecated in 10.9 */

- (void)_logErrorWithTitle:(NSString *)title AndMessage:(NSString *)message
{
    NSLog(@"[ERROR] %@ %@", title, message);
    exit(1);
}

- (void)_logStatus:(NSString *)line
{
    NSLog(@"%@", line);
}

@end
