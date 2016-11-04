//
//  SRReSign.h
//  iReSignCommand
//
//  Created by rexshi on 6/17/14.
//  Copyright (c) 2014 rexshi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SRReSign : NSObject
{
    NSUserDefaults *defaults;
    
    NSTask *unzipTask;
    NSTask *provisioningTask;
    NSTask *codesignTask;
    NSTask *verifyTask;
    NSTask *zipTask;
    NSString *originalIpaPath;
    NSString *outputIpaPath;
    NSString *appPath;
    NSString *workingPath;
    NSString *appName;
    NSString *fileName;
    
    NSString *codesigningResult;
    NSString *verificationResult;
    
    NSString *provisioningPath;
    NSString *resourceRulesPath;
    NSString *entitlementPath;
    NSString *bundleIDNew;
    NSString *certName;
    
    NSMutableArray *installedCertItems;
    NSTask *certTask;
    NSArray *getCertsResult;
    
}

@property (nonatomic, strong) NSString *certName;
@property (nonatomic, strong) NSString *originalIpaPath;
@property (nonatomic, strong) NSString *outputIpaPath;
@property (nonatomic, strong) NSString *workingPath;

- (void)checkUnzip:(NSTimer *)timer;
- (void)doProvisioning;
- (void)checkProvisioning:(NSTimer *)timer;
- (void)doCodeSigning;
- (void)checkCodesigning:(NSTimer *)timer;
- (void)doVerifySignature;
- (void)checkVerificationProcess:(NSTimer *)timer;
- (void)doZip;
- (void)checkZip:(NSTimer *)timer;
- (void)disableControls;
- (void)enableControls;

- (void)resign;

@end
