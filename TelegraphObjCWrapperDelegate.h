#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TelegraphObjCWrapperDelegate <NSObject>
@optional
- (void)telegraphServerDidStartWithHost:(NSString *)host port:(NSInteger)port;
- (void)telegraphServerDidStopWithError:(NSError * _Nullable)error;
- (void)telegraphClientDidConnectWithClientIdentifier:(NSString *)clientIdentifier;
- (void)telegraphClientDidDisconnectWithClientIdentifier:(NSString *)clientIdentifier error:(NSError * _Nullable)error;
- (void)telegraphDidReceiveTextWithClientIdentifier:(NSString *)clientIdentifier text:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
