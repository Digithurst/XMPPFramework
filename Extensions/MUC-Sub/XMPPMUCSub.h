//
//  XMPPMUCSub.h
//  XMPPFramework
//
//  Created by Robert Lohr on 06.10.2017.
//

#import <Foundation/Foundation.h>
#import "XMPPModule.h"

#ifndef MUCSub_h
#define MUCSub_h

@class XMPPIQ;
@class XMPPJID;
@class XMPPMessage;
@class XMPPPresence;

/**
 * The XMPPMUCSub provides functionality to a proprietary Multi User Chat extension of 
 * the ejabberd XMPP server. This extension aims to provide a solution to the problem
 * that users are required to send a presence to a MUC room in oder to receive messages.
 * By subscribing to the room a user can also participate if not online. Once reconnected,
 * missed messages are synced.
 * 
 * The extension leverages several existing extension to achieve its task. More details
 * can be found on the project's website.
 * 
 * https://docs.ejabberd.im/developer/xmpp-clients-bots/proposed-extensions/muc-sub/
 * 
 * MUC-Sub can be enabled by creating an instance of `XMPPMUCSub` and activating it on 
 * the `XMPPStream`.
**/
@interface XMPPMUCSub : XMPPModule
{
/*  Inherited from XMPPModule:
    
    XMPPStream *xmppStream;
    
    dispatch_queue_t
    id multicastDelegate;
*/
}

/* Inherited from XMPPModule:
 
- (BOOL)activate:(XMPPStream *)xmppStream;
- (void)deactivate;

@property (readonly) XMPPStream *xmppStream;
 
- (void)addDelegate:(id)delegate delegateQueue:(dispatch_queue_t)delegateQueue;
- (void)removeDelegate:(id)delegate delegateQueue:(dispatch_queue_t)delegateQueue;
- (void)removeDelegate:(id)delegate;
- (NSString *)moduleName;
 
*/

// MARK: Subscription Management

/**
 * Subscribes the currently logged in user to the specified room.
**/
- (NSString*)subscribeTo:(XMPPJID*)room;

/**
 * Unsubscribes the currently logged in user from the specified room.
**/
- (NSString*)unsubscribeFrom:(XMPPJID*)room;

/**
 * Subscribes `user` to the specified room. The logged in user has to be moderator in the 
 * room to perform this task.
**/
- (NSString*)subscribe:(XMPPJID*)user to:(XMPPJID*)room;

/**
 * Unsubscribes `user` to the specified room. The logged in user has to be moderator in 
 * the room to perform this task.
**/
- (NSString*)unsubscribe:(XMPPJID*)user from:(XMPPJID*)room;

/**
 * Get a list of all the rooms the current user is subscribed to.
**/
- (NSString*)subscriptions;

/**
 * Get a list of all the users that have subscribed to the specified room. The logged in user 
 * has to be moderator in the room to perform this task.
**/
- (NSString*)subscribers:(XMPPJID*)room;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Defines the callback methods a client may want to implement to receive notifications about 
 * actions that were performed and their respective result.
 * 
 * Simply create a new delegate instance and call `XMPPMUCSub.addDelegate:delegate:delegateQueue`.
**/
@protocol XMPPMUCSubDelegate
@optional

/**
 * The user has been subscribed to a specific room. It is not differentiated between 
 * subscribing oneself or another user. Both result in this method being called on 
 * success.
**/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didSubscribeUser:(XMPPJID*)user to:(XMPPJID*)room;

/**
 * The subscription process failed. It is not differentiated between subscribing oneself
 * or another user. Both result in this method being called on failure.
**/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didFailToSubscribe:(XMPPJID*)user to:(XMPPJID*)room 
             error:(NSError*)error;


/**
 * The user has been unsubscribed to a specific room. It is not differentiated between 
 * unsubscribing oneself or another user. Both result in this method being called on 
 * success.
 **/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didUnsubscribeUser:(XMPPJID*)user to:(XMPPJID*)room;

/**
 * The unsubscription process failed. It is not differentiated between unsubscribing 
 * oneself or another user. Both result in this method being called on failure.
 **/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didFailToUnsubscribe:(XMPPJID*)user to:(XMPPJID*)room 
             error:(NSError*)error;

/**
 * Called in response to `[XMPPMUCSub subscriptions]`. Returns an array of room `XMPPJID`
 * objects the current user is subscribed to.
**/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didReceiveSubscriptions:(NSArray*)subscriptions;

/**
 * Called in response to `[XMPPMUCSub subscriptions]` if fetching the subscriptions failed.
 **/
- (void)xmppMUCSubDidFailToReceiveSubscriptions:(XMPPMUCSub*)sender error:(NSError*)error;

/**
 * Called in response to `[XMPPMUCSub subscribers:]`. Returns an array of user `XMPPJID`
 * objects that are subscribed to the specified room.
 **/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didReceiveSubscribers:(NSArray*)subscribers to:(XMPPJID*)room;

/**
 * Called in response to `[XMPPMUCSub subscribers:]`. Returns an array of user `XMPPJID`
 * objects that are subscribed to the specified room.
 **/
- (void)xmppMUCSubDidFailToReceiveSubscribers:(XMPPMUCSub*)sender to:(XMPPJID*)room 
                                        error:(NSError*)error;

/**
 * Called when a message has been received. The message is parsed from MUC-Sub format and
 * returned as regular `XMPPMessage` for easy consumption.
**/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didReceiveMessage:(XMPPMessage*)message;

/**
 * Called when a presence has been received. The presence is parsed from MUC-Sub format and
 * returned as regular `XMPPPresence` for easy consumption.
 **/
- (void)xmppMUCSub:(XMPPMUCSub*)sender didReceivePresence:(XMPPPresence*)presence;

@end

#endif /* MUCSub_h */
