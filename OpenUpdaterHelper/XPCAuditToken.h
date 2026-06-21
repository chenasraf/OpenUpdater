//
//  XPCAuditToken.h
//  OpenUpdaterHelper
//
//  Created by Chen Asraf on 21/06/2026.
//
//  Exposes the connecting peer's audit token to Swift. NSXPCConnection.auditToken
//  exists at runtime but isn't in the public headers / Swift overlay, so we bridge
//  it here. The audit token (unlike a PID) can't be spoofed or reused by the caller.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The peer's audit token as NSData, for `SecCodeCopyGuestWithAttributes` with
/// `kSecGuestAttributeAudit`. Returns nil if unavailable.
NSData *_Nullable OUCopyAuditToken(NSXPCConnection *connection);

NS_ASSUME_NONNULL_END
