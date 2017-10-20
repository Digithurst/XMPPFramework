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
@class XMPPElement;

/**
 * The XMPPMUCSub provides support for a proprietary Multi User Chat extension of the
 * ejabberd XMPP server. This extension aims to provide a solution to the problem that 
 * users are required to send a presence to a MUC room in order to receive messages. By 
 * subscribing to the room a user can also participate if not online. Once reconnected,
 * missed messages are synced.
 * 
 * Users can, of course, also join the room as before. From the project specification:
 * 
 * "If a user wants to be present in the room, he just have to join the room as defined 
 * in XEP-0045. A subscriber MAY decide to join a conference (in the XEP-0045 sense). In 
 * this case a conference MUST behave as described in XEP-0045 7.2 Entering a Room. A 
 * conference MUST process events as described under XEP-0045 7.1 Order of Events except 
 * it MUST not send room history. When a subscriber is joined, a conference MUST stop 
 * sending subscription events and MUST switch to a regular groupchat protocol (as 
 * described in XEP-0045) until a subscriber leaves."
 * 
 * The extension leverages several existing XEPs to achieve its task. More details can be 
 * found on the project's website (as of 09.10.2017).
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
    XMPPIDTracker *xmppIDTracker;
}

// MARK: Service Discovery

/**
 * Query whether MUC-Sub is enabled on a room.
 * 
 * @param room
 *        The `XMPPRoom` for which to check if MUC-Sub has been enabled.
 * 
 * @return
 * Returns the randomly generated "id" attribute value of the standard <iq> element that 
 * is sent in case client code may want to do manual tracking. `nil` if `room` is `nil`
 * or there is no active connection (`[XMPPStream isConnected]`).
 *
 * @see `[XMPPMUCSub xmppMUCSub:serviceSupportedBy:]`, 
 *      `[XMPPMUCSub xmppMUCSub:serviceNotSupportedBy:]`,
 *      `[XMPPMUCSub xmppMUCSub:didFailToReceiveSupportedBy:error:]`
**/
- (nullable NSString *)supportedBy:(nonnull XMPPRoom *)room;

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
 * Returns the randomly generated "id" attribute value of the standard <iq> element that 
 * is sent in case client code may want to do manual tracking. `nil` if `room` is `nil`
 * or there is no active connection (`[XMPPStream isConnected]`).
**/
- (nullable NSString *)subscribeTo:(nonnull XMPPJID *)room nick:(nullable NSString *)nick 
                          password:(nullable NSString *)pass;

/**
 * Unsubscribes the currently logged in user from the specified room.
 * 
 * @param room
 *        The room's JID to which oneself unsubscribes from.
 * 
 * @return
 * Returns the randomly generated "id" attribute value of the standard <iq> element that 
 * is sent in case client code may want to do manual tracking. `nil` if `room` is `nil`
 * or there is no active connection (`[XMPPStream isConnected]`).
**/
- (nullable NSString *)unsubscribeFrom:(nonnull XMPPJID *)room;

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
 *        The nickname of `user` in the room. If `nil`, the bare JID is used.
 * 
 * @param pass
 *        If the room is secured with a password it needs to be specified. Otherwise
 *        `nil`.
 * 
 * @return
 * Returns the randomly generated "id" attribute value of the standard <iq> element that 
 * is sent in case client code may want to do manual tracking. `nil` if `user` and/or 
 * `room` are `nil` or there is no active connection (`[XMPPStream isConnected]`).
**/
- (nullable NSString *)subscribe:(nonnull XMPPJID *)user to:(nonnull XMPPJID *)room 
                            nick:(nullable NSString *)nick password:(nullable NSString *)pass;

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
 * Returns the randomly generated "id" attribute value of the standard <iq> element that 
 * is sent in case client code may want to do manual tracking. `nil` if `user` and/or 
 * `room` are `nil` or there is no active connection (`[XMPPStream isConnected]`).
**/
- (nullable NSString *)unsubscribe:(nonnull XMPPJID *)user from:(nonnull XMPPJID *)room;

/**
 * Get a list of all the rooms the current user is subscribed to.
 * 
 * @param domain
 *        URL of the service providing the MUC functionality. Can be retrieved using
 *        service discovery. Typical examples may start with "muc." or "conference.".
 * 
 * @return
 * Returns the randomly generated "id" attribute value of the standard <iq> element that 
 * is sent in case client code may want to do manual tracking. `nil` if `domain` is `nil`
 * or there is no active connection (`[XMPPStream isConnected]`).
**/
- (nullable NSString *)subscriptionsAt:(nonnull NSString *)domain;

/**
 * Get a list of all the users that have subscribed to the specified room. The logged in user 
 * has to be moderator in the room to perform this task.
 * 
 * @return
 * Returns the randomly generated "id" attribute value of the standard <iq> element that 
 * is sent in case client code may want to do manual tracking. `nil` if `room` is nil or
 * there is no active connection (`[XMPPStream isConnected]`).
**/
- (nullable NSString *)subscribersOf:(nonnull XMPPJID *)room;

/**
 * Checks if the given element is a MUC-Sub encapsulated element.
 * 
 * @param element
 *        An `XMPPElement`, e.g. a message or presence, that was received.
 * 
 * @return
 * `TRUE` if the element is MUC-Sub encapsulated or `FALSE` if not.
**/
+ (BOOL)isMUCSubElement:(nonnull XMPPElement *)element;

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
 * The user has been subscribed from a specific room. It is not differentiated between 
 * subscribing oneself or another user. Both result in this method being called on 
 * success.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didSubscribeUser:(nonnull XMPPJID *)user
          withNick:(nullable NSString *)nick 
                to:(nonnull XMPPJID *)room;

/**
 * The subscription process failed. It is not differentiated between subscribing oneself
 * or another user. Both result in this method being called on failure.
 *
 * Note: If a moderator subscribes another user then `user` is the JID of the moderator. 
 *       That's because that is the user to which the request is sent to. You best rely
 *       on the `nick`.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didFailToSubscribeUser:(nonnull XMPPJID *)user
          withNick:(nullable NSString *)nick 
                to:(nonnull XMPPJID *)room 
             error:(nonnull NSError *)error;


/**
 * The user has been unsubscribed from a specific room. It is not differentiated between 
 * unsubscribing oneself or another user. Both result in this method being called on 
 * success.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didUnsubscribeUser:(nonnull XMPPJID *)user 
              from:(nonnull XMPPJID *)room;

/**
 * The unsubscription process failed. It is not differentiated between unsubscribing 
 * oneself or another user. Both result in this method being called on failure.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didFailToUnsubscribeUser:(nonnull XMPPJID *)user 
              from:(nonnull XMPPJID *)room 
             error:(nonnull NSError *)error;

/**
 * Called in response to `[XMPPMUCSub subscriptions]`. Returns an array of room `XMPPJID`
 * objects the current user is subscribed to.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didReceiveSubscriptionsAt:(nonnull NSArray *)subscriptions;

/**
 * Called in response to `[XMPPMUCSub subscriptions]` if fetching the subscriptions failed.
**/
- (void)xmppMUCSubDidFailToReceiveSubscriptionsAt:(nonnull XMPPMUCSub *)sender 
                                            error:(nonnull NSError *)error;

/**
 * Called in response to `[XMPPMUCSub subscribers:]`. Returns an array of user `XMPPJID`
 * objects that are subscribed to the specified room.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didReceiveSubscribersIn:(nonnull NSArray *)subscribers 
                to:(nonnull XMPPJID *)room;

/**
 * Called in response to `[XMPPMUCSub subscribers:]`. Returns an array of user `XMPPJID`
 * objects that are subscribed to the specified room.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didFailToReceiveSubscribersOf:(nonnull XMPPJID *)room 
             error:(nonnull NSError *)error;

/**
 * Called when a message has been received. The message is parsed from MUC-Sub format and
 * returned as regular `XMPPMessage` for easy consumption.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didReceiveMessage:(nonnull XMPPMessage *)message;

/**
 * Called when a presence has been received. The presence is parsed from MUC-Sub format and
 * returned as regular `XMPPPresence` for easy consumption.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didReceivePresence:(nonnull XMPPPresence *)presence;

/**
 * Called when the MUC-Sub service is supported by a specific room. This is a response to
 * a client calling `[XMPPMUCSub supportedBy:]`.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender serviceSupportedBy:(nonnull XMPPJID *)room;

/**
 * Called when the MUC-Sub service is not supported by a specific room. This is a response 
 * to a client calling `[XMPPMUCSub supportedBy:]`.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender serviceNotSupportedBy:(nonnull XMPPJID *)room;

/**
 * Called when the MUC-Sub server responds with an error `[XMPPMUCSub supportedBy:]`.
**/
- (void)xmppMUCSub:(nonnull XMPPMUCSub *)sender didFailToReceiveSupportedBy:(nonnull XMPPJID *)room
             error:(nonnull NSError *)error;

@end

#endif /* MUCSub_h */
