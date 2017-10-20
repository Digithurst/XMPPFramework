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
#import "XMPPRoom.h"

#if ! __has_feature(objc_arc)
    #warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#if DEBUG
    static const int xmppLogLevel = XMPP_LOG_FLAG_TRACE; // | XMPP_LOG_FLAG_TRACE;
#else
    static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

static NSString *const XMPPPubSubNamespace = @"http://jabber.org/protocol/pubsub#event";
static NSString *const XMPPMUCSubNamespace = @"urn:xmpp:mucsub:0";
static NSString *const XMPPMUCSubFeaturesPrefix = @"urn:xmpp:mucsub:nodes:";
static int XMPPIDTrackerTimout = 60;

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

- (NSString *)supportedBy:(XMPPRoom *)room
{
    if (nil == room) {
        return nil;
    }
    
    // <iq from='hag66@shakespeare.example/pda'
    //       to='coven@muc.shakespeare.example'
    //     type='get'
    //       id='ik3vs715'>
    //   <query xmlns='http://jabber.org/protocol/disco#info'/>
    // </iq>
    
    NSString *iqId = [XMPPStream generateUUID];
    
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *query = [NSXMLElement elementWithName:@"query" xmlns:XMPPDiscoInfoNamespace];
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"get" elementID:iqId];
        [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.full];
        [iq addAttributeWithName:@"to"   stringValue:room.roomJID.bare];
        
        [iq addChild:query];
        
        [xmppIDTracker addElement:iq target:self selector:@selector(handleSupportedByIQ:withInfo:) 
                          timeout:XMPPIDTrackerTimout];
        [xmppStream sendElement:iq];
    }};

    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }

    return iqId;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)subscribeTo:(XMPPJID *)room nick:(NSString *)nick password:(NSString *)pass
{
    return [self subscribe:xmppStream.myJID to:room nick:nick password:pass];
}


- (NSString *)unsubscribeFrom:(XMPPJID *)room
{
    return [self unsubscribe:xmppStream.myJID from:room];
}


- (NSString *)subscribe:(XMPPJID *)user to:(XMPPJID *)room nick:(NSString *)nick
               password:(NSString *)pass
{
    if (nil == user || nil == room || !xmppStream.isConnected) {
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
    
    NSString *iqId = [XMPPStream generateUUID];
    
    dispatch_block_t block = ^{ @autoreleasepool {
        NSString* usedNick = nick;
        if (nil == nick) {
            usedNick = user.bare;
        }
        
        // Build the request from the inside out.
        NSXMLElement *messages = [NSXMLElement elementWithName:@"event"];
        [messages addAttributeWithName:@"node" stringValue:@"urn:xmpp:mucsub:nodes:messages"];
        
        NSXMLElement *presence = [NSXMLElement elementWithName:@"event"];
        [presence addAttributeWithName:@"node" stringValue:@"urn:xmpp:mucsub:nodes:presence"];
        
        
        NSXMLElement *subscribe = [NSXMLElement elementWithName:@"subscribe" xmlns:XMPPMUCSubNamespace];
        [subscribe addAttributeWithName:@"nick" stringValue:usedNick];
        
        // Subscribe self or somebody else? If somebody else then JID has to be added to <subscribe>.
        if (![xmppStream.myJID.bare isEqualToString:user.bare]) {
            [subscribe addAttributeWithName:@"jid" stringValue:user.bare];
        }
        if (nil != pass) {
            [subscribe addAttributeWithName:@"password" stringValue:pass];
        }

        [subscribe addChild:messages];
        [subscribe addChild:presence];
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:iqId];
        // Current user in from is always correct. Either as self or as moderator.
        [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
        [iq addAttributeWithName:@"to"   stringValue:room.bare];
        
        [iq addChild:subscribe];
        
        [xmppIDTracker addElement:iq target:self selector:@selector(handleSubscribeQueryIQ:withInfo:) 
                          timeout:XMPPIDTrackerTimout];
        [xmppStream sendElement:iq];
    }};

    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }

    return iqId;
}


- (NSString *)unsubscribe:(XMPPJID *)user from:(XMPPJID *)room
{
    if (nil == user || nil == room || !xmppStream.isConnected) {
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
    
    NSString *iqId = [XMPPStream generateUUID];
    
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *unsubscribe = [NSXMLElement elementWithName:@"unsubscribe" 
                                                            xmlns:XMPPMUCSubNamespace];
        // Unsubscribe self or somebody else? If somebody else then JID has to be added to 
        // <unsubscribe>.
        if (![xmppStream.myJID.bare isEqualToString:user.bare]) {
            [unsubscribe addAttributeWithName:@"jid" stringValue:user.bare];
        }
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"set" elementID:iqId];
        // Current user in from is always correct. Either as self or as moderator.
        [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
        [iq addAttributeWithName:@"to"   stringValue:room.bare];
        
        [iq addChild:unsubscribe];
        
        [xmppIDTracker addElement:iq target:self selector:@selector(handleUnsubscribeQueryIQ:withInfo:) 
                          timeout:XMPPIDTrackerTimout];
        [xmppStream sendElement:iq];
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
    
    return iqId;
}


- (NSString *)subscriptionsAt:(NSString *)domain
{
    if (nil == domain || !xmppStream.isConnected) {
        return nil;
    }
    
    // <iq from='hag66@shakespeare.example'
    //       to='muc.shakespeare.example'
    //     type='get'
    //       id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
    //   <subscriptions xmlns='urn:xmpp:mucsub:0' />
    // </iq>
    
    NSString *iqId = [XMPPStream generateUUID];
    
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *subscriptions = [NSXMLElement elementWithName:@"subscriptions"
                                                              xmlns:XMPPMUCSubNamespace];
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"get" elementID:iqId];
        [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
        [iq addAttributeWithName:@"to"   stringValue:domain];
        
        [iq addChild:subscriptions];
        
        [xmppIDTracker addElement:iq target:self selector:@selector(handleSubscriptionsAtQueryIQ:withInfo:) 
                          timeout:XMPPIDTrackerTimout];
        [xmppStream sendElement:iq];
    }};

    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }

    return iqId;
}


- (NSString *)subscribersOf:(XMPPJID *)room
{
    if (nil == room || !xmppStream.isConnected) {
        return nil;
    }
    
    // <iq from='hag66@shakespeare.example'
    //       to='coven@muc.shakespeare.example'
    //     type='get'
    //       id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
    //   <subscriptions xmlns='urn:xmpp:mucsub:0' />
    // </iq>
    
    NSString *iqId = [XMPPStream generateUUID];
    
    dispatch_block_t block = ^{ @autoreleasepool {
        NSXMLElement *subscriptions = [NSXMLElement elementWithName:@"subscriptions"
                                                              xmlns:XMPPMUCSubNamespace];
        
        XMPPIQ *iq = [XMPPIQ iqWithType:@"get" elementID:iqId];
        [iq addAttributeWithName:@"from" stringValue:xmppStream.myJID.bare];
        [iq addAttributeWithName:@"to"   stringValue:room.bare];
        
        [iq addChild:subscriptions];
        
        [xmppIDTracker addElement:iq target:self selector:@selector(handleSubscribersInQueryIQ:withInfo:) 
                          timeout:XMPPIDTrackerTimout];
        [xmppStream sendElement:iq];
    }};
    
    if (dispatch_get_specific(moduleQueueTag)) {
        block();
    }
    else {
        dispatch_async(moduleQueue, block);
    }
    
    return iqId;
}


+ (BOOL)isMUCSubElement:(nonnull XMPPElement *)element
{
    NSXMLElement *item = [self findMUCSubItemsElement:element forEvent:@""];
    return nil != item;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark XMPPIDTracker
////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)handleSubscribeQueryIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)basicTrackingInfo
{
    dispatch_block_t block = ^{ @autoreleasepool {
        // Extract the values of the original request. Only this way we can make sure we
        // have the correct information. If we find "jid" in <subscribe> then we take that.
        // It means a mod subscribed another user. If not, then we use <iq "from">. It means
        // a user subscribed himself/herself.
        XMPPElement *request = basicTrackingInfo.element;
        NSXMLElement *subscribe = [request elementForName:@"subscribe" xmlns:XMPPMUCSubNamespace];
        
        NSString *nick = [subscribe attributeStringValueForName:@"nick"];
        NSString *jid  = [subscribe attributeStringValueForName:@"jid"];
        
        XMPPJID *user = nil;
        if (nil != jid)  {
            user = [XMPPJID jidWithString:jid];
        }
        else {
            user = request.from;
        }
        
        if (iq.isResultIQ) {
            [multicastDelegate xmppMUCSub:self didSubscribeUser:user withNick:nick to:request.to];
        }
        else {
            [multicastDelegate xmppMUCSub:self didFailToSubscribeUser:user 
                                 withNick:nick
                                       to:request.to 
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
        // Extract the values of the original request. Only this way we can make sure we
        // have the correct information. If we find "jid" in <subscribe> then we take that.
        // It means a mod subscribed another user. If not, then we use <iq "from">. It means
        // a user subscribed himself/herself.
        XMPPElement *request = basicTrackingInfo.element;
        NSXMLElement *subscribe = [request elementForName:@"unsubscribe" xmlns:XMPPMUCSubNamespace];
        
        NSString *jid  = [subscribe attributeStringValueForName:@"jid"];
        
        XMPPJID *user = nil;
        if (nil != jid)  {
            user = [XMPPJID jidWithString:jid];
        }
        else {
            user = request.from;
        }
        
        if (iq.isResultIQ) {
            [multicastDelegate xmppMUCSub:self didUnsubscribeUser:user from:iq.from];
        }
        else {
            [multicastDelegate xmppMUCSub:self didFailToUnsubscribeUser:user 
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
            [multicastDelegate xmppMUCSub:self didFailToReceiveSubscribersOf:iq.from
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


- (void)handleSupportedByIQ:(XMPPIQ *)iq withInfo:(XMPPBasicTrackingInfo *)basicTrackingInfo
{
    // <iq from='coven@muc.shakespeare.example'
    //       to='hag66@shakespeare.example/pda'
    //     type='result'
    //       id='ik3vs715'>
    //   <query xmlns='http://jabber.org/protocol/disco#info'>
    //     <identity category='conference'
    //                   name='A Dark Cave'
    //                   type='text' />
    //     <feature var='http://jabber.org/protocol/muc' />
    //     ...
    //     <feature var='urn:xmpp:mucsub:0' />
    //     ...
    //   </query>
    // </iq>
    
    dispatch_block_t block = ^{ @autoreleasepool {
        if (iq.isResultIQ) {
            NSXMLElement *query = [iq elementForName:@"query" xmlns:XMPPDiscoInfoNamespace];
            for (NSXMLNode *child in query.children) {
                if ([@"feature" isEqualToString:child.name] && NSXMLElementKind == child.kind) {
                    NSString *var = [(NSXMLElement *)child attributeStringValueForName:@"var"];
                    if ([XMPPMUCSubNamespace isEqualToString:var]) {
                        [multicastDelegate xmppMUCSub:self serviceSupportedBy:iq.from];
                        return;
                    }
                }
            }
            
            [multicastDelegate xmppMUCSub:self serviceNotSupportedBy:iq.from];
        }
        else {
            [multicastDelegate xmppMUCSub:self didFailToReceiveSupportedBy:iq.from
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
    //
    // or for presences
    //
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
    
    dispatch_block_t block = nil;
    NSXMLElement* items = nil;
    
    static NSString *messagesEvent = @"messages";
    static NSString *presenceEvent = @"presence";
    
    NSArray<NSString *> *events = @[messagesEvent, presenceEvent];
    NSString *event = nil;
    for (event in events) {
        if ((items = [XMPPMUCSub findMUCSubItemsElement:message forEvent:event])) {
            break;
        }
    }
    
    if (nil != items && nil != event) {
        // All preconditions show that it's a MUC-Sub message. Extract the original message
        // or presence (or?) and forward it to the registered delegates.
        block = ^{ @autoreleasepool {
            for (NSXMLNode *item in items.children) {
                NSXMLNode* node = [item childAtIndex:0];
                if (nil == node) {
                    continue;
                }
                
                if (NSXMLElementKind != node.kind) {
                    continue;
                }
                
                if ([event isEqualToString:messagesEvent]) {
                    XMPPMessage *m = [XMPPMessage messageFromElement:(NSXMLElement *)node];
                    [multicastDelegate xmppMUCSub:self didReceiveMessage:m];
                }
                else if ([event isEqualToString:presenceEvent]) {
                    XMPPPresence *p = [XMPPPresence presenceFromElement:(NSXMLElement *)node];
                    [multicastDelegate xmppMUCSub:self didReceivePresence:p];
                }
            }
        }};
    }
    
    if (nil != block) {
        if (dispatch_get_specific(moduleQueueTag)) {
            block();
        }
        else {
            dispatch_async(moduleQueue, block);
        }
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
    // <iq from='muc.shakespeare.example'
    //       to='hag66@shakespeare.example'
    //     type='result'
    //       id='E6E10350-76CF-40C6-B91B-1EA08C332FC7'>
    //   <subscriptions xmlns='urn:xmpp:mucsub:0'>
    //     <subscription jid='coven@muc.shakespeare.example' />
    //     <subscription jid='chat@muc.shakespeare.example' />
    //   </subscriptions>
    // </iq>
    
    NSXMLElement *subscriptions = [iq elementForName:@"subscriptions" xmlns:XMPPMUCSubNamespace];
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


+ (NSXMLElement *)findMUCSubItemsElement:(XMPPElement *)element forEvent:(NSString *)event
{
    NSXMLElement *eventElement = [element elementForName:@"event" xmlns:XMPPPubSubNamespace];
    if (nil == eventElement) {
        return nil;
    }
    
    NSXMLElement *mucsubItems = [eventElement elementForName:@"items"];
    if (nil == mucsubItems) {
        return nil;
    }
    
    // Check start of attribute is good enough since it's internal. This way we can also
    // return an element if "node" starts with `XMPPMUCSubFeaturesPrefix`. This is helpful
    // for `[XMPPMUCSub isMUCSubElement:]`. Other queries pass an event which makes them
    // exact.
    NSString* mucsubString = [XMPPMUCSubFeaturesPrefix stringByAppendingString:event];
    if (![[mucsubItems attributeStringValueForName:@"node"] hasPrefix:mucsubString]) {
        return nil;
    }
    
    return mucsubItems;
}

@end
