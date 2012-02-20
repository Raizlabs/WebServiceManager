//
//  WebServiceRequest.h
//  WebServiceManager
//
//  Created by Craig Spitzkoff on 10/21/11.
//  Copyright (c) 2011 Raizlabs Corporation. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString* const kURLkey;
extern NSString* const kHTTPMethodKey;
extern NSString* const kExpectedResultTypeKey;
extern NSString* const kFailureHandlerKey;
extern NSString* const kSuccessHandlerKey;


@protocol WebServiceRequestDelegate;
@class RZWebServiceManager;

@interface RZWebServiceRequest : NSOperation <NSURLConnectionDelegate>
{
@private
    NSMutableDictionary* _headers;
}

-(id) initWithApiInfo:(NSDictionary*)apiInfo target:(id)target;
-(id) initWithApiInfo:(NSDictionary *)apiInfo target:(id)target parameters:(NSDictionary*)parameters;

// create a request
-(id) initWithURL:(NSURL*)url 
       httpMethod:(NSString*)httpMethod
        andTarget:(id)target 
  successCallback:(SEL)successCallback
  failureCallback:(SEL)failureCallback
expectedResultType:(NSString*)expectedResultType
    andParameters:(NSDictionary*)parameters;

// set a request header on the outgoing request
-(void) setValue:(NSString*)value forHTTPHeaderField:(NSString*)headerField;

@property (unsafe_unretained, nonatomic) id target;
@property (assign, nonatomic) SEL successHandler;
@property (assign, nonatomic) SEL failureHandler;
@property (strong, nonatomic) NSMutableURLRequest* urlRequest;
@property (strong, nonatomic) NSURL* url;
@property (strong, nonatomic) NSString* httpMethod;
@property (strong, nonatomic) NSString* expectedResultType;
@property (strong, nonatomic) NSMutableArray* parameters;
@property (strong, nonatomic) NSDictionary* userInfo;

// if you'd like to stream to disk, set a target filename where the data
// can be saved. This will prevent the data from being kept in memory.
@property (strong, nonatomic) NSURL* targetFileURL;

// data returned by the web service
@property (strong, readonly) NSData* data;

// request headers to be sent with the request. Only use dictionaries of string/string key value pairs
@property (strong, nonatomic) NSDictionary* headers;

@property (unsafe_unretained, nonatomic) id<WebServiceRequestDelegate> delegate;
@property (strong, nonatomic) NSDictionary* responseHeaders;
@end


@protocol WebServiceRequestDelegate <NSObject>

-(void) webServiceRequest:(RZWebServiceRequest*)request failedWithError:(NSError*)error;
-(void) webServiceRequest:(RZWebServiceRequest *)request completedWithData:(NSData*)data;

@end