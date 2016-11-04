//
//  main.m
//  iReSignCommand
//
//  Created by rexshi on 6/17/14.
//  Copyright (c) 2014 rexshi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SRReSign.h"

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        if (argc != 4) {
            printf("Usage: iparesign <cret_name> <provisioning_path> <entitlement_path> <old_ipa_path> <output_ipa_path> <unzipc_path>\n");
            exit(1);
        }
        
        SRReSign *resign = [[SRReSign alloc] init];
        resign.certName = [NSString stringWithUTF8String:argv[1]];
        resign.provisioningPath = [NSString stringWithUTF8String:argv[2]];
        resign.entitlementPath = [NSString stringWithUTF8String:argv[3]];
        resign.originalIpaPath = [NSString stringWithUTF8String:argv[4]];
        resign.outputIpaPath = [NSString stringWithUTF8String:argv[5]];
        resign.unzipcPath = [NSString stringWithUTF8String:argv[6]];
 
        [resign resign];
        
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}

