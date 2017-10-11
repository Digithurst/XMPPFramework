//
//  XMPPMUCSub.m
//  XMPPFramework
//
//  Created by Robert Lohr on 09.10.2017.
//

#import <Foundation/Foundation.h>
#import "XMPPMUCSub.h"
#import "XMPP.h"
#import "XMPPIDTracker.h"
#import "XMPPLogging.h"
#import "XMPPFramework.h"

#if ! __has_feature(objc_arc)
    #warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#if DEBUG
    static const int xmppLogLevel = XMPP_LOG_FLAG_TRACE; // | XMPP_LOG_FLAG_TRACE;
#else
    static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

static NSString* PUBSUB_EVENT_XMLNS = @"http://jabber.org/protocol/pubsub#event";
static NSString* MUCSUB_NS_PREFIX = @"urn:xmpp:mucsub:nodes:";

@interface XMPPMUCSub (PrivateAPI)

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XMPPMUCSub

- (id)init
{
    return [self initWithDispatchQueue:nil];
}

- (id)initWithDispatchQueue:(dispatch_queue_t)queue
{
    return [super initWithDispatchQueue:queue];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)activate:(XMPPStream *)aXmppStream
{
    XMPPLogTrace();
    
    if ([super activate:aXmppStream]) {
        XMPPLogVerbose(@"%@: Activated", THIS_FILE);
        
        // xmppStream set by call to super.activate. moduleQueue set by super.init.
        xmppIDTracker = [[XMPPIDTracker alloc] initWithStream:xmppStream dispatchQueue:moduleQueue];
        return TRUE;
    }
    
    return FALSE;
}

- (void)deactivate
{
    XMPPLogTrace();
    
    dispatch_block_t block = ^{ @autoreleasepool {
        [xmppIDTracker removeAllIDs];
        xmppIDTracker = nil;
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_sync(moduleQueue, block);
    }
    
    [super deactivate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)subscribeTo:(XMPPJID *)room nick:(NSString *)nick password:(NSString *)pass
{
    return [self subscribe:xmppStream.myJID to:room nick:nick password:pass];
}


- (NSString*)unsubscribeFrom:(XMPPJID * )room
{
    return [self unsubscribe:xmppStream.myJID from:room];
}


- (NSString *)subscribe:(XMPPJID *)user to:(XMPPJID *)room nick:(NSString *)nick
               password:(NSString *)pass
{
    if (nil == user || nil == room) {
        return nil;
    }
    
    // <iq from='hag66@shakespeare.example'
    //       to='coven@muc.shakespeare.example'
    //     type='set'
    //       id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
    //   <subscribe xmlns='urn:xmpp:mucsub:0'
    //                jid='hag66@shakespeare.example' <- Optional, see comment below.
    //               nick='mynick'
    //           password='roompassword'>
    //     <event node='urn:xmpp:mucsub:nodes:messages' />
    //     <event node='urn:xmpp:mucsub:nodes:presence' />
    //   </subscribe>
    // </iq>
    
    // If current user subscribes herself/himself then <iq from> is that user's JID and 
    // <subscribe> does not have a JID. If current user subscribes someone else, i.e.
    // she/he is a moderator (otherwise server complains), then <iq from> is the moderator's
    // JID and <subscribe jid> is the user that shall be subscribed.
    
    if (nil == nick) {
        nick = user.bare;
    }
    
    // Build the request from the inside out.
    NSXMLElement *messages = [NSXMLElement elementWithName:@"event"];
    [messages addAttributeWithName:@"node" stringValue:@"urn:xmpp:mucsub:nodes:messages"];
    
    NSXMLElement *presence = [NSXMLElement elementWithName:@"node"];
    [presence addAttributeWithName:@"node" stringValue:@"urn:xmpp:mucsub:nodes:presence"];
    
    
    NSXMLElement *subscribe = [NSXMLElement elementWithName:@"subscribe" xmlns:@"urn:xmpp:mucsub:0"];
    [subscribe addAttributeWithName:@"nick" stringValue:nick];
    
    // Subscribe self or somebody else? If somebody else then JID has to be added to <subscribe>.
    if (![xmppStream.myJID.bare isEqualToString:user.bare]) {
        [subscribe addAttributeWithName:@"jid" stringValue:user.bare];
    }
    if (nil != pass) {
        [subscribe addAttributeWithName:@"password" stringValue:pass];
    }

    [subscribe addChild:messages];
    [subscribe addChild:presence];
    
    
    NSString *iqId = [XMPPStream generateUUID];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:iqId];
    // Current user in from is always correct. Either as self or as moderator.
    [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
    [iq addAttributeWithName:@"to"   stringValue:room.bare];
    
    [iq addChild:subscribe];
    
    [xmppIDTracker addElement:iq target:self selector:@selector(handleSubscribeQueryIQ:withInfo:) 
                      timeout:60];
    [xmppStream sendElement:iq];
    
    return iqId;
}


- (NSString *)unsubscribe:(XMPPJID *)user from:(XMPPJID *)room
{
    if (nil == user || nil == room) {
        return nil;
    }
    
    // <iq from='king@shakespeare.example'
    //       to='coven@muc.shakespeare.example'
    //     type='set'
    //       id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
    //   <unsubscribe xmlns='urn:xmpp:mucsub:0'
    //                  jid='hag66@shakespeare.example'/>  <- Optional, see comment below
    // </iq>
    
    // If current user unsubscribes herself/himself then <iq from> is that user's JID and 
    // <unsubscribe> does not have a JID. If current user unsubscribes someone else, i.e.
    // she/he is a moderator (otherwise server complains), then <iq from> is the moderator's
    // JID and <unsubscribe jid> is the user that shall be unsubscribed.
    
    NSXMLElement *unsubscribe = [NSXMLElement elementWithName:@"unsubscribe" 
                                                        xmlns:@"urn:xmpp:mucsub:0"];
    // Unsubscribe self or somebody else? If somebody else then JID has to be added to 
    // <unsubscribe>.
    if (![xmppStream.myJID.bare isEqualToString:user.bare]) {
        [unsubscribe addAttributeWithName:@"jid" stringValue:user.bare];
    }
    
    
    NSString *iqId = [XMPPStream generateUUID];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:iqId];
    // Current user in from is always correct. Either as self or as moderator.
    [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
    [iq addAttributeWithName:@"to"   stringValue:room.bare];
    
    [iq addChild:unsubscribe];
    
    [xmppIDTracker addElement:iq target:self selector:@selector(handleUnsubscribeQueryIQ:withInfo:) 
                      timeout:60];
    [xmppStream sendElement:iq];
    
    return iqId;
}


- (NSString *)subscriptionsAt:(NSString *)domain
{
    if (nil == domain) {
        return nil;
    }
    
    // <iq from='hag66@shakespeare.example'
    //       to='muc.shakespeare.example'
    //     type='get'
    //       id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
    //   <subscriptions xmlns='urn:xmpp:mucsub:0' />
    // </iq>
    
    NSXMLElement *subscriptions = [NSXMLElement elementWithName:@"subscriptions"
                                                          xmlns:@"urn:xmpp:mucsub:0"];
    
    NSString *iqId = [XMPPStream generateUUID];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get" elementID:iqId];
    [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
    [iq addAttributeWithName:@"to"   stringValue:domain];
    
    [iq addChild:subscriptions];
    
    [xmppIDTracker addElement:iq target:self selector:@selector(handleSubscriptionsAtQueryIQ:withInfo:) 
                      timeout:60];
    [xmppStream sendElement:iq];
    
    return iqId;
}


- (NSString *)subscribersIn:(XMPPJID *)room
{
    if (nil == room) {
        return nil;
    }
    
    // <iq from='hag66@shakespeare.example'
    //       to='coven@muc.shakespeare.example'
    //     type='get'
    //       id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
    //   <subscriptions xmlns='urn:xmpp:mucsub:0' />
    // </iq>
    
    NSXMLElement *subscriptions = [NSXMLElement elementWithName:@"subscriptions"
                                                          xmlns:@"urn:xmpp:mucsub:0"];
    
    NSString *iqId = [XMPPStream generateUUID];
    
    XMPPIQ *iq = [XMPPIQ iqWithType:@"get" elementID:iqId];
    [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
    [iq addAttributeWithName:@"to"   stringValue:room.bare];
    
    [iq addChild:subscriptions];
    
    [xmppIDTracker addElement:iq target:self selector:@selector(handleSubscribersInQueryIQ:withInfo:) 
                      timeout:60];
    [xmppStream sendElement:iq];
    
    return iqId;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark XMPPIDTracker
////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleSubscribeQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)basicTrackingInfo
{
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *query = [iq elementForName:@"subscribe" xmlns:@"urn:xmpp:mucsub:0"];
        if (nil == query) {
            // Can this actually happen? Still, safeguard for my conscience.
            return;
        }
        
        // "to" and "from" are the other way around in the response. Therefore the function
        // call reads a bit funny. "to" is the receiving user and "from" the sending room.
        if (iq.isResultIQ) {
            [multicastDelegate xmppMUCSub:self didSubscribeUser:iq.to to:iq.from];
        }
        else {
            [multicastDelegate xmppMUCSub:self didFailToSubscribe:iq.to 
                                       to:iq.from 
                                    error:[self errorFromIQ:iq]];
        }
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
}


- (void)handleUnsubscribeQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)basicTrackingInfo
{
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *query = [iq elementForName:@"unsubscribe" xmlns:@"urn:xmpp:mucsub:0"];
        if (nil == query) {
            // Must have been another request with the same id?
            // Can this actually happen? Still, safeguard for my conscience.
            return;
        }
        
        // "to" and "from" are the other way around in the response. Therefore the function
        // call reads a bit funny. "to" is the receiving user and "from" the sending room.
        if (iq.isResultIQ) {
            [multicastDelegate xmppMUCSub:self didUnsubscribeUser:iq.to from:iq.from];
        }
        else {
            [multicastDelegate xmppMUCSub:self didFailToUnsubscribe:iq.to 
                                       from:iq.from 
                                    error:[self errorFromIQ:iq]];
        }
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
}


- (void)handleSubscriptionsAtQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)basicTrackingInfo
{
    dispatch_block_t block = ^{ @autoreleasepool {
        if (iq.isResultIQ) {
            NSArray<XMPPJID *>* rooms = [self jidFromSubscriptionIQ:iq];
            if (nil == rooms) {
                // Must have been another request with the same id?
                // Can this actually happen? Still, safeguard for my conscience.
                return;
            }
            
            [multicastDelegate xmppMUCSub:self didReceiveSubscriptionsAt:rooms];
        }
        else {
            [multicastDelegate xmppMUCSubDidFailToReceiveSubscriptionsAt:self 
                                                                   error:[self errorFromIQ:iq]];
        }
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
}


- (void)handleSubscribersInQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)basicTrackingInfo
{
    dispatch_block_t block = ^{ @autoreleasepool {
        if (iq.isResultIQ) {
            NSArray<XMPPJID *>* rooms = [self jidFromSubscriptionIQ:iq];
            if (nil == rooms) {
                // Must have been another request with the same id?
                // Can this actually happen? Still, safeguard for my conscience.
                return;
            }
            
            [multicastDelegate xmppMUCSub:self didReceiveSubscribersIn:rooms to:iq.from];
        }
        else {
            [multicastDelegate xmppMUCSubDidFailToReceiveSubscribersIn:self to:iq.from
                                                                 error:[self errorFromIQ:iq]];
        }
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Message + Presence Delegate
////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq
{
    NSString *type = iq.type;
    
    if ([type isEqualToString:@"result"] || [type isEqualToString:@"error"]) {
        return [xmppIDTracker invokeForID:iq.elementID withObject:iq];
    }
    
    return NO;
}


- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    // <message from="coven@muc.shakespeare.example"
    //            to="hag66@shakespeare.example/pda">
    //   <event xmlns="http://jabber.org/protocol/pubsub#event">
    //     <items node="urn:xmpp:mucsub:nodes:messages">
    //       <item id="18277869892147515942">
    //         <message from="coven@muc.shakespeare.example/secondwitch"
    //                    to="hag66@shakespeare.example/pda"
    //                  type="groupchat"
    //                 xmlns="jabber:client">
    //           <archived xmlns="urn:xmpp:mam:tmp"
    //                        by="muc.shakespeare.example"
    //                        id="1467896732929849" />
    //           <stanza-id xmlns="urn:xmpp:sid:0"
    //                         by="muc.shakespeare.example"
    //                         id="1467896732929849" />
    //           <body>Hello from the MUC room !</body>
    //         </message>
    //       </item>
    //     </items>
    //   </event>
    // </message>
    
    NSXMLElement* items = [self findMUCSubItemsElement:message forEvent:@"messages"];
    if (nil == items) {
        return;
    }
    
    // All preconditions show that it's a MUC-Sub message. Extract the original message
    // and forward it to the registered delegates. The message may contain several <item>
    // elements and thus several original <message> elements.
    dispatch_block_t block = ^{ @autoreleasepool {
        for (NSXMLNode *item in items.children) {
            NSXMLNode* messageNode = [item childAtIndex:0];
            if (nil == messageNode) {
                continue;
            }
            
            if (NSXMLElementKind != messageNode.kind) {
                continue;
            }
            
            XMPPMessage *m = [XMPPMessage messageFromElement:(NSXMLElement *)messageNode];
            [multicastDelegate xmppStream:sender didReceiveMessage:m];
        }
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
}


- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence
{
    // <message from="coven@muc.shakespeare.example"
    //            to="hag66@shakespeare.example/pda">
    //   <event xmlns="http://jabber.org/protocol/pubsub#event">
    //     <items node="urn:xmpp:mucsub:nodes:presences">
    //       <item id="8170705750417052518">
    //         <presence xmlns="jabber:client"
    //                    from="coven@muc.shakespeare.example/secondwitch"
    //                    type="unavailable"
    //                      to="hag66@shakespeare.example/pda">
    //           <x xmlns="http://jabber.org/protocol/muc#user">
    //             <item affiliation="none" role="none" />
    //           </x>
    //         </presence>
    //       </item>
    //     </items>
    //   </event>
    // </message>
    
    NSXMLElement* items = [self findMUCSubItemsElement:presence forEvent:@"presences"];
    if (nil == items) {
        return;
    }
    
    // All preconditions show that it's a MUC-Sub message. Extract the original message
    // and forward it to the registered delegates. The message may contain several <item>
    // elements and thus several original <message> elements.
    dispatch_block_t block = ^{ @autoreleasepool {
        for (NSXMLNode *item in items.children) {
            NSXMLNode* presenceNode = [item childAtIndex:0];
            if (nil == presenceNode) {
                continue;
            }
            
            if (NSXMLElementKind != presenceNode.kind) {
                continue;
            }
            
            XMPPPresence *p = [XMPPPresence presenceFromElement:(NSXMLElement *)presenceNode];
            [multicastDelegate xmppStream:sender didReceivePresence:p];
        }
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Helpers
////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorFromIQ:(XMPPIQ *)iq
{
    // An error may look like this.
    // 
    // <iq xmlns="jabber:client" 
    //      lang="de" 
    //        to="hag66@shakespeare.example" 
    //      from="coven@muc.shakespeare.example" 
    //      type="error" 
    //        id="23EAAB2B-F6BD-4CA0-9539-DAE495ED5885">
    //   <subscriptions xmlns="urn:xmpp:mucsub:0"/>
    //   <error code="403" type="auth">
    //     <forbidden xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/>
    //     <text xmlns="urn:ietf:params:xml:ns:xmpp-stanzas" lang="de">
    //       Moderatorrechte benötigt
    //     </text>
    //   </error>
    // </iq>
    
    if ([iq isErrorIQ]) {
        NSXMLElement* error = [iq childErrorElement];
        
        NSString *reason = nil;      // Must be filled.
        NSString *description = nil; // May be filled.
        
        for (NSXMLNode *child in error.children) {
            // If there is a <text> node we can get a useful description. Otherwise
            // we have to live with the generic <forbidden> (from the example above).
            // Errors types may vary, of course.
            if ([child.name isEqualToString:@"text"]) {
                description = child.stringValue;
            }
            else {
                reason = child.name;
            }
        }
        
        return [[NSError alloc] initWithDomain:XMPPStreamErrorDomain 
                                          code:XMPPStreamInvalidState 
                                      userInfo:@{reason: description}];
    }
    
    return nil;
}


- (NSArray<XMPPJID *>*)jidFromSubscriptionIQ:(XMPPIQ *)iq
{
    NSXMLElement *subscriptions = [iq elementForName:@"subscriptions" xmlns:@"urn:xmpp:mucsub:0"];
    if (nil == subscriptions) {
        return nil;
    }
    
    NSMutableArray<XMPPJID *> *rooms = [[NSMutableArray alloc] init];
    for (NSXMLNode *subscription in subscriptions.children) {
        if (NSXMLElementKind == subscription.kind) {
            NSXMLElement *element = (NSXMLElement *)subscription;
            NSString *jid = [element attributeStringValueForName:@"jid"];
            [rooms addObject:[XMPPJID jidWithString:jid]];
        }
    }
    return rooms;
}


- (NSXMLElement *)findMUCSubItemsElement:(XMPPElement *)element forEvent:(NSString *)event
{
    NSXMLElement *eventElement = [element elementForName:@"event" xmlns:PUBSUB_EVENT_XMLNS];
    if (nil == eventElement) {
        return nil;
    }
    
    NSXMLElement *mucsubItems = [eventElement elementForName:@"items"];
    if (nil == mucsubItems) {
        return nil;
    }
    
    NSString* mucsubString = [MUCSUB_NS_PREFIX stringByAppendingString:event];
    if (![[mucsubItems attributeStringValueForName:@"node"] isEqualToString:mucsubString]) {
        return nil;
    }
    
    return mucsubItems;
}

@end
