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

@class XMPPIDTracker;
@class XMPPIQ;
@class XMPPJID;
@class XMPPMessage;
@class XMPPPresence;
@class XMPPRoom;

/**
 * The XMPPMUCSub provides functionality to a proprietary Multi User Chat extension of 
 * the ejabberd XMPP server. This extension aims to provide a solution to the problem
 * that users are required to send a presence to a MUC room in oder to receive messages.
 * By subscribing to the room a user can also participate if not online. Once reconnected,
 * missed messages are synced.
 * 
 * The extension leverages several existing extension to achieve its task. More details
 * can be found on the project's website (as of 09.10.2017).
 * 
 * https://docs.ejabberd.im/developer/xmpp-clients-bots/proposed-extensions/muc-sub/
 * 
 * One note about subscriptions (taken from the ejabberd documentation):
 * Subscription is associated with a nick. It will implicitly register the nick. Server 
 * should otherwise make sure that subscription match the user registered nickname in 
 * that room. In order to change the nick and/or subscription nodes, the same request 
 * MUST be sent with a different nick or nodes information.
 *
 * This means that clients need to provide the nickname of the user in the MUC room
 * when subscribing. If none is given then the bare JID will be used.
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
    
    XMPPIDTracker *xmppIDTracker;
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

// MARK: Service Discovery

/**
 * Query whether MUC-Sub is enabled on a room.
 * 
 * @param room
 *        The `XMPPRoom` for which to check if MUC-Sub has been enabled.
 * 
 * @return
 * The request id of the IQ is in case client code may want to do manual tracking. `nil`
 * if `room` is `nil`.
 *
 * @see `[XMPPMUCSub xmppMUCSub:serviceSupportedBy:]`, 
 *      `[XMPPMUCSub xmppMUCSub:serviceNotSupportedBy:]`,
 *      `[XMPPMUCSub xmppMUCSub:didFailToReceiveSupportedBy:error:]`
**/
- (NSString *)supportedBy:(XMPPRoom *)room;

// MARK: Subscription Management

/**
 * Subscribes the currently logged in user to the specified room.
 * 
 * @param room
 *        The room's JID to which oneself subscribes to.
 * 
 * @param nick
 *        Ones nickname in the room. If `nil`, the bare JID is used.
 * 
 * @param pass
 *        If the room is secured with a password it needs to be specified. Otherwise
 *        `nil`.
 * 
 * @return
 * The request id of the IQ is in case client code may want to do manual tracking. `nil`
 * if `room` is `nil`.
**/
- (NSString *)subscribeTo:(XMPPJID *)room nick:(NSString *)nick password:(NSString *)pass;

/**
 * Unsubscribes the currently logged in user from the specified room.
 * 
 * @param room
 *        The room's JID to which oneself unsubscribes from.
 * 
 * @return
 * The request id of the IQ is returned in case client code may want to do manual 
 * tracking. `nil` if `room` is `nil`.
**/
- (NSString *)unsubscribeFrom:(XMPPJID *)room;

/**
 * Subscribes `user` to the specified room.
 * 
 * @param user
 *        The user that shall be subscribed to a room. This can be the current user 
 *        (also see `subscribeTo:nick:password:`) or another user. In the latter case 
 *        the current user must be moderator in the room.
 * 
 * @param room
 *        The room's JID to which `user` subscribes to.
 * 
 * @param nick
 *        Ones nickname in the room. If `nil`, the bare JID is used.
 * 
 * @param pass
 *        If the room is secured with a password it needs to be specified. Otherwise
 *        `nil`.
 * 
 * @return
 * The request id of the IQ is returned in case client code may want to do manual 
 * tracking. `nil` if `user` and/or `room` are `nil`.
**/
- (NSString *)subscribe:(XMPPJID *)user to:(XMPPJID *)room nick:(NSString *)nick 
               password:(NSString *)pass;

/**
 * Unsubscribes `user` from the specified room.
 * 
 * @param user
 *        The user that shall be unsubscribed from a room. This can be the current user 
 *        (also see `unsubscribeFrom:`) or another user. In the latter case the current 
 *        user must be moderator in the room.
 * 
 * @param room
 *        The room's JID from which `user` unsubscribes.
 * 
 * @return
 * The request id of the IQ is returned in case client code may want to do manual 
 * tracking. `nil` if `user` and/or `room` are `nil`.
**/
- (NSString *)unsubscribe:(XMPPJID *)user from:(XMPPJID *)room;

/**
 * Get a list of all the rooms the current user is subscribed to.
 * 
 * @param domain
 *        URL of the service providing the MUC functionality. Can be retrieved using
 *        service discovery. Typical examples may start with "muc." or "conference.".
 * 
 * @return
 * The request id of the IQ is returned in case client code may want to do manual 
 * tracking.
**/
- (NSString *)subscriptionsAt:(NSString *)domain;

/**
 * Get a list of all the users that have subscribed to the specified room. The logged in user 
 * has to be moderator in the room to perform this task.
 * 
 * @return
 * The request id of the IQ is returned in case client code may want to do manual 
 * tracking.
**/
- (NSString *)subscribersIn:(XMPPJID *)room;

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
- (void)xmppMUCSub:(XMPPMUCSub *)sender didSubscribeUser:(XMPPJID *)user to:(XMPPJID *)room;

/**
 * The subscription process failed. It is not differentiated between subscribing oneself
 * or another user. Both result in this method being called on failure.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didFailToSubscribe:(XMPPJID *)user to:(XMPPJID *)room 
             error:(NSError *)error;


/**
 * The user has been unsubscribed to a specific room. It is not differentiated between 
 * unsubscribing oneself or another user. Both result in this method being called on 
 * success.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didUnsubscribeUser:(XMPPJID *)user from:(XMPPJID *)room;

/**
 * The unsubscription process failed. It is not differentiated between unsubscribing 
 * oneself or another user. Both result in this method being called on failure.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didFailToUnsubscribe:(XMPPJID *)user from:(XMPPJID *)room 
             error:(NSError *)error;

/**
 * Called in response to `[XMPPMUCSub subscriptions]`. Returns an array of room `XMPPJID`
 * objects the current user is subscribed to.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didReceiveSubscriptionsAt:(NSArray *)subscriptions;

/**
 * Called in response to `[XMPPMUCSub subscriptions]` if fetching the subscriptions failed.
**/
- (void)xmppMUCSubDidFailToReceiveSubscriptionsAt:(XMPPMUCSub *)sender error:(NSError *)error;

/**
 * Called in response to `[XMPPMUCSub subscribers:]`. Returns an array of user `XMPPJID`
 * objects that are subscribed to the specified room.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didReceiveSubscribersIn:(NSArray *)subscribers 
                to:(XMPPJID *)room;

/**
 * Called in response to `[XMPPMUCSub subscribers:]`. Returns an array of user `XMPPJID`
 * objects that are subscribed to the specified room.
**/
- (void)xmppMUCSubDidFailToReceiveSubscribersIn:(XMPPMUCSub *)sender to:(XMPPJID *)room 
                                          error:(NSError *)error;

/**
 * Called when a message has been received. The message is parsed from MUC-Sub format and
 * returned as regular `XMPPMessage` for easy consumption.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didReceiveMessage:(XMPPMessage *)message;

/**
 * Called when a presence has been received. The presence is parsed from MUC-Sub format and
 * returned as regular `XMPPPresence` for easy consumption.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didReceivePresence:(XMPPPresence *)presence;

/**
 * Called when the MUC-Sub service is supported by a specific room. This is a response to
 * a client calling `[XMPPMUCSub supportedBy:]`.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender serviceSupportedBy:(XMPPJID *)room;

/**
 * Called when the MUC-Sub service is not supported by a specific room. This is a response 
 * to a client calling `[XMPPMUCSub supportedBy:]`.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender serviceNotSupportedBy:(XMPPJID *)room;

/**
 * Called when the MUC-Sub server responds with an error `[XMPPMUCSub supportedBy:]`.
**/
- (void)xmppMUCSub:(XMPPMUCSub *)sender didFailToReceiveSupportedBy:(XMPPJID *)room
             error:(NSError *)error;

@end

#endif /* MUCSub_h */
