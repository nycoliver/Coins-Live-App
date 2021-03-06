//
//  OFMarketData.m
//  Coins Live
//
//  Created by O on 6/10/14.
//  Copyright (c) 2014 O. All rights reserved.
//

#import "OFMarketData.h"
#import <Pusher/Pusher.h>
#import "PricePoint.h"

@interface OFMarketData () <PTPusherDelegate>
@property NSMutableDictionary *markets;
@property PTPusher *pusherClient;
@property NSInteger lastUpdated;
@property BOOL fetchedPrice;
@end

@implementation OFMarketData

- (id)initWithMarkets:(NSArray *)markets
{
    self = [super init];
    if (self) {
        [self connectPusher];
        [self loadMarkets:markets];
        [self fetchAvailableMarkets];
        [self fetchHistoricalPrices];
    }
    return self;
}

#pragma Market Info

- (CGFloat)price:(NSString *)market
{
    Market *m = [self marketWithSymbol:market];
    return m.price;
}

-(CGFloat)lastPrice:(NSString *)market
{
    Market *m = [self marketWithSymbol:market];
    return m.lastPrice;
}

- (NSString *)displayName:(NSString *)market
{
    Market *m = [self marketWithSymbol:market];
    return m.displayName;
}

- (NSString *)currency:(NSString *)market
{
    Market *m = [self marketWithSymbol:market];
    return m.currency;
}

- (NSString *)item:(NSString *)market
{
    Market *m = [self marketWithSymbol:market];
    return m.item;
}

- (Market *)marketWithSymbol:(NSString *)symbol
{
    return [self.markets objectForKey:symbol];
}

- (NSArray *)subscribedMarkets
{
    NSMutableArray *markets = [@[] mutableCopy];
    for (NSString *m in self.markets) {
        Market *market = self.markets[m];
        if (market.subscribed)
            [markets addObject:m];
    }
    return markets;
}

- (NSArray *)availableMarkets
{
    NSMutableArray *markets = [@[] mutableCopy];
    for (NSString *m in self.markets) {
        Market *market = self.markets[m];
        if (!market.subscribed)
            [markets addObject:m];
    }
    return [markets sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}



#pragma Pusher

- (void)subscribeToMarket:(NSString *)market
{
    [self.pusherClient subscribeToChannelNamed:market];
    Market *m = [self marketWithSymbol:market];
    m.subscribed = YES;
}

- (void)unsubscribeFromMarket:(NSString *)market
{
    PTPusherChannel *channel = [self.pusherClient channelNamed:market];
    [channel unsubscribe];
    Market *m = [self marketWithSymbol:market];
    m.subscribed = NO;
}


#pragma Price History

- (void)fetchHistoricalPrices
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"markets": [self subscribedMarkets]}
                                                   options:0
                                                     error:&error];
    
    if (json) {
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
        [request setURL:[NSURL URLWithString:@"http://history.coinslive.io/prices"]];
        [request setHTTPMethod:@"POST"];
        [request setValue:[NSString stringWithFormat:@"%lu",(unsigned long)[json length]]
       forHTTPHeaderField:@"Content-Length"];
        [request setValue:@"application/json"
       forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:json];
        
        NSDictionary *ranges = @{@"h": @3600,
                                 @"d": @86400,
                                 @"w": @604800,
                                 @"m": @2592000,
                                 @"y": @31536000};
        
        
        [NSURLConnection sendAsynchronousRequest: request
                                           queue: [NSOperationQueue mainQueue]
                               completionHandler: ^(NSURLResponse *r, NSData *data, NSError *error) {
                                   
                                   [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                                   
                                   NSError *err = nil;
                                   if (data) {
                                       NSDictionary *res = [NSJSONSerialization JSONObjectWithData:data
                                                                                           options:0
                                                                                             error:&err];
                                       for (NSString *m in res) {
                                           Market *market = [self.markets objectForKey:m];
                                           for (NSString *range2 in res[m]) {
                                               NSMutableArray *prices = [@[] mutableCopy];
                                               for (NSArray *p in res[m][range2])
                                                   [prices addObject:[PricePoint make:p]];
                                               [market setPrices:prices forRange:[ranges[range2] integerValue]];
                                           }
                                           [[NSNotificationCenter defaultCenter] postNotificationName:@"prices"
                                                                                               object:nil
                                                                                             userInfo:@{@"symbol": market.symbol}];
                                           //self.lastUpdated = [[NSDate date] timeIntervalSince1970];
                                       }
                                       self.fetchedPrice = YES;
                                   }
                                   else {
                                       double delayInSeconds = 2.0;
                                       dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                                       dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                                           [self fetchHistoricalPrices];
                                       });
                                       
                                   }
                               }];
    } else {
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self fetchHistoricalPrices];
        });
    }
    
    [self.pusherClient connect];
    for (NSString *m in self.markets) {
        Market *market = self.markets[m];
        if (market.subscribed)
            [self subscribeToMarket:m];
    }
}

- (CGFloat)percentChange:(NSString *)market inRange:(NSInteger)range
{
    Market *m = [self marketWithSymbol:market];
    PricePoint *firstPrice;
    if ([[m pricesInRange:range] count] > 1)
        firstPrice = [m pricesInRange:range][1];
    else
        firstPrice = [[m pricesInRange:range] firstObject];
    CGFloat amount = m.price - firstPrice.price;
    CGFloat change = amount/m.price*100;
    return change;
}

- (CGFloat)amountChange:(NSString *)market inRange:(NSInteger)range
{
    Market *m = [self marketWithSymbol:market];
    PricePoint *firstPrice;
    if ([[m pricesInRange:range] count] > 1)
        firstPrice = [m pricesInRange:range][1];
    else
        firstPrice = [[m pricesInRange:range] firstObject];
    CGFloat amount = m.price - firstPrice.price;
    return amount;
}

- (NSArray *)prices:(NSString *)market inRange:(NSInteger)range
{
    Market *m = [self marketWithSymbol:market];
    return [m pricesInRange:range];
}


#pragma Init

- (void)connectPusher
{
    self.pusherClient = [PTPusher pusherWithKey:@"772e3efac9290a5818b7" delegate:self encrypted:NO];
    [self.pusherClient bindToEventNamed:@"price" handleWithBlock:^(PTPusherEvent *event) {
        //NSLog(@"%@", event.channel);
        if (self.fetchedPrice) {
            Market *market = [self marketWithSymbol:event.channel];
            PricePoint *price = [[PricePoint alloc] initWithJSON:event.data];
            [market updatePrice:price];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"price"
                                                                object:nil
                                                              userInfo:@{@"symbol": market.symbol}];
        }
        
    }];
    [self.pusherClient connect];
}

- (BOOL)pusher:(PTPusher *)pusher connectionWillAutomaticallyReconnect:(PTPusherConnection *)connection afterDelay:(NSTimeInterval)delay
{
    //NSLog(@"WillReconnect");
    return YES;
}

- (void)pusher:(PTPusher *)pusher connection:(PTPusherConnection *)connection didDisconnectWithError:(NSError *)error willAttemptReconnect:(BOOL)willAttemptReconnect
{
    //NSLog(@"DidDisconnect");
    [self.pusherClient connect];
    for (NSString *m in self.markets) {
        Market *market = self.markets[m];
        if (market.subscribed) {
            //NSLog(@"Subscribing to %@", market.symbol);
            [self subscribeToMarket:m];
        }
    }
}

- (void)pusher:(PTPusher *)pusher connectionDidConnect:(PTPusherConnection *)connection
{
    //NSLog(@"CONNECTED");
}

- (void)loadMarkets:(NSArray *)markets
{
    self.markets = [@{} mutableCopy];
    for (NSString *symbol in markets) {
        Market *market = [[Market alloc] initWithSymbol:symbol];
        market.subscribed = YES;
        [self.markets setObject:market forKey:symbol];
        [self subscribeToMarket:market.symbol];
    }
}

- (void)fetchAvailableMarkets
{
    NSArray *temp = @[//@"anxbtcBTCHKD",
                      //@"anxbtcBTCJPY",
                      
                      @"1coinBTCUSD",
                      @"bitstampBTCUSD",
                      @"btceBTCUSD",
                      @"btceBTCEUR",
                      @"btceBTCRUR",
                      @"bitcurexBTCEUR",
                      @"bitcurexBTCPLN",
                      
                      @"bitfinexBTCUSD",
                      @"btcchinaBTCCNY",
                      @"btcdeBTCEUR",
                      @"campbxBTCUSD",
                      @"coinbaseBTCUSD",
                      
                      @"huobiBTCCNY",
                      @"hitbtcBTCUSD",
                      @"hitbtcBTCEUR",
                      @"itbitBTCUSD",
                      
                      @"lakebtcBTCUSD",
                      @"localbtcBTCUSD",
                      @"localbtcBTCGBP",
                      @"okcoinBTCCNY",
                      
                      @"korbitBTCKRW",
                      
                      
                      @"bit2cBTCNIS",
                      @"krakenBTCUSD",
                      @"krakenBTCEUR",
                      @"virtexBTCCAD"];
    
    
    for (NSString *symbol in temp) {
        Market *market = [[Market alloc] initWithSymbol:symbol];
        if (![self.markets objectForKey:symbol]) {
            market.subscribed = NO;
            [self.markets setObject:market forKey:symbol];
        }
    }
}



@end
