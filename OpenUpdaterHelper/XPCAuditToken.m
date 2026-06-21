//
//  XPCAuditToken.m
//  OpenUpdaterHelper
//
//  Created by Chen Asraf on 21/06/2026.
//

#import "XPCAuditToken.h"
#import <bsm/libbsm.h>

// `auditToken` is implemented by NSXPCConnection but not declared in the public
// headers. Declaring it in a category lets the compiler read it. macOS 11+.
@interface NSXPCConnection (OUAuditToken)
@property (nonatomic, readonly) audit_token_t auditToken;
@end

NSData *_Nullable OUCopyAuditToken(NSXPCConnection *connection) {
  audit_token_t token = connection.auditToken;
  return [NSData dataWithBytes:&token length:sizeof(token)];
}
