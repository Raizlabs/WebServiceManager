//
//  WebServiceRequest.m
//  WebServiceManager
//
//  Created by Craig Spitzkoff on 10/21/11.
//  Copyright (c) 2011 Raizlabs Corporation. All rights reserved.
//

#import "RZWebServiceRequest.h"
#import "RZWebService_NSURL.h"

NSString *const kURLkey = @"URL";
NSString *const kHTTPMethodKey = @"Method";
NSString *const kExpectedResultTypeKey = @"ExpectedResultType";
NSString *const kFailureHandlerKey = @"FailureHandler";
NSString *const kSuccessHandlerKey = @"SuccessHandler";
NSString *const kTimeoutKey = @"Timeout";

NSTimeInterval const kDefaultTimeout = 60;

@interface RZWebServiceRequest()

@property (strong, nonatomic) NSMutableData* receivedData;
@property (assign, readwrite) NSUInteger bytesReceived;
@property (strong, nonatomic) NSURLConnection* connection;
@property (assign, nonatomic) float responseSize;
@property (assign, nonatomic) BOOL done;
@property (assign, nonatomic) BOOL finished;
@property (assign, nonatomic) BOOL executing;

// if the user has chosen to stream to a file, a targetFileHandle will be created
@property (strong, nonatomic) NSFileHandle* targetFileHandle;

// selector used to trigger timeouts. 
@property (assign, nonatomic) SEL timeoutSelector;

-(void) beginOperation;

// report an error to the delegate. 
-(void) reportError:(NSError*)error;

// schedule the next timeout interval.
-(void) scheduleTimeout;

// cancel any scheduled timeout. 
-(void) cancelTimeout;

@end


@implementation RZWebServiceRequest
@synthesize target = _target;
@synthesize httpMethod = _httpMethod;
@synthesize receivedData = _receivedData;
@synthesize bytesReceived = _bytesReceived;
@synthesize connection = _connection;
@synthesize url = _url;
@synthesize delegate  = _delegate;
@synthesize successHandler = _successHandler;
@synthesize failureHandler = _failureHandler;
@synthesize parameters = _parameters;
@synthesize urlRequest = _urlRequest;
@synthesize expectedResultType = _expectedResultType;
@synthesize responseHeaders = _responseHeaders;
@synthesize headers = _headers;
@synthesize userInfo = _userInfo;
@synthesize targetFileURL = _targetFileURL;
@synthesize targetFileHandle = _targetFileHandle;
@synthesize responseSize = _responseSize;
@synthesize timeoutInterval = _timeoutInterval;
@synthesize timeoutSelector = _timeoutSelector;

@synthesize done = _done;
@synthesize finished = _finished;
@synthesize executing = _executing;

-(id) initWithApiInfo:(NSDictionary *)apiInfo target:(id)target
{
    self = [self initWithApiInfo:apiInfo target:target parameters:nil];

    return self;
}

-(id) initWithApiInfo:(NSDictionary *)apiInfo target:(id)target parameters:(NSDictionary*)parameters
{
    NSURL* url = [NSURL URLWithString:[apiInfo objectForKey:kURLkey]];
    NSString* httpMethod = [apiInfo objectForKey:kHTTPMethodKey];
    NSString* expectedResultType = [apiInfo objectForKey:kExpectedResultTypeKey];
    SEL successCallback = NSSelectorFromString([apiInfo objectForKey:kSuccessHandlerKey]);
    SEL failureCallback = NSSelectorFromString([apiInfo objectForKey:kFailureHandlerKey]);
    
    self.timeoutInterval = [[apiInfo objectForKey:kTimeoutKey] doubleValue];
    
    self = [self initWithURL:url
                  httpMethod:httpMethod
                   andTarget:target
             successCallback:successCallback
             failureCallback:failureCallback
          expectedResultType:expectedResultType
               andParameters:parameters];
    
    return self;
}

-(id) initWithURL:(NSURL*)url 
       httpMethod:(NSString*)httpMethod
        andTarget:(id)target 
  successCallback:(SEL)successCallback
  failureCallback:(SEL)failureCallback
expectedResultType:(NSString*)expectedResultType
    andParameters:(NSDictionary*)parameters
{
    self = [super init];
    
    if (nil != self) {
        self.url = url;
        self.httpMethod = httpMethod;
        self.target = target;
        self.successHandler = successCallback;
        self.failureHandler = failureCallback;
        self.expectedResultType = expectedResultType;

        // convert the parameters to a sorted array of parameter objects
        NSArray* sortedKeys = [[parameters allKeys] sortedArrayUsingSelector:@selector(compare:)];
        self.parameters = [NSMutableArray arrayWithCapacity:sortedKeys.count];

        for (NSString* key in sortedKeys) {
            NSDictionary* parameter = [NSDictionary dictionaryWithObjectsAndKeys:key, kRZURLParameterNameKey, [parameters objectForKey:key], kRZURLParameterValueKey, nil];
            [self.parameters addObject:parameter];
        }
 
        self.urlRequest = [[NSMutableURLRequest alloc] initWithURL:self.url];
    }
    
    return self;
}

-(void) setValue:(NSString*)value forHTTPHeaderField:(NSString*)headerField
{
    if(nil == value || nil == headerField)
        return;
    
    if(nil == _headers)
        _headers = [NSMutableDictionary dictionaryWithCapacity:1];
    
    [_headers setValue:value forKey:headerField];
}

-(void) setHeaders:(NSDictionary *)headers
{
    _headers = [headers mutableCopy];
}

-(NSDictionary*) headers
{
    if(nil == _headers)
        return nil;

    return  [NSDictionary dictionaryWithDictionary:_headers];
}

-(void) start
{
    if (self.isCancelled) {
        
        // If it's already been cancelled, mark the operation as finished.
        [self willChangeValueForKey:@"isFinished"];
        self.finished = YES;
        [self didChangeValueForKey:@"isFinished"];
    }
    
    [self willChangeValueForKey:@"isExecuting"];
      
    [NSThread detachNewThreadSelector:@selector(beginOperation) toTarget:self withObject:nil];

}

-(void) beginOperation
{
    
    @autoreleasepool {
        
        self.bytesReceived = 0;
        
        _executing = YES;
        [self didChangeValueForKey:@"isExecuting"];    
        
        self.urlRequest.HTTPMethod = self.httpMethod;
        
        
        // if this is a get request and there are parameters, format them as part of the URL, and reset the URL on the request. 
        if(self.parameters && self.parameters.count > 0)
        {
            if ([self.httpMethod isEqualToString:@"GET"]) {
                self.urlRequest.URL = [self.url URLByAddingParameters:self.parameters];
            }
            else if([self.httpMethod isEqualToString:@"POST"])
            {
                // set the post body to the formatted parameters. 
                self.urlRequest.HTTPBody = [[NSURL URLQueryStringFromParameters:self.parameters] dataUsingEncoding:NSUTF8StringEncoding];
            }
            
        }
        
        // add the string/string pairs as headers.
        for (id key in self.headers) {
            id value = [self.headers objectForKey:key];
            if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
                [self.urlRequest setValue:value forHTTPHeaderField:key];
            }

        }
        
        // if the expected type is JSON, we should add a header declaring we accept that type. 
        if ([[self.expectedResultType uppercaseString] isEqualToString:@"JSON"]) {
            [self.urlRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        }
        
        // create and start the connection.
        self.connection = [[NSURLConnection alloc] initWithRequest:self.urlRequest delegate:self startImmediately:YES];

        // setup our timeout callback. 
        if(self.timeoutInterval <= 0)
            self.timeoutInterval = kDefaultTimeout;
        [self scheduleTimeout];
        
        [self didChangeValueForKey:@"isExecuting"];
        
        while (!self.done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
        
        [self willChangeValueForKey:@"isFinished"];
        [self willChangeValueForKey:@"isExecuting"];
        
        _finished = YES;
        _executing = NO;
        
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];

    }
}

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isExecuting {
    return _executing;
}

- (BOOL)isFinished {
    return _finished;
}

-(void) cancel
{
    [super cancel];
    [self.connection cancel];
}

-(void) timeout
{
    // TODO: flesh out the userInfo dictionary passed to create the error. 
    NSError* error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
    
    [self reportError:error];
    
    self.done = YES;
    [self cancel];
}


-(void) cancelTimeout
{
    if(nil != self.timeoutSelector)
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:self.timeoutSelector object:nil];    
}

-(void) scheduleTimeout
{
    [self cancelTimeout];
    
    if (nil == self.timeoutSelector) {
        self.timeoutSelector =  @selector(timeout);
    }

    [self performSelector:self.timeoutSelector withObject:nil afterDelay:self.timeoutInterval];   
}

-(NSData*) data
{
    return [[NSData alloc] initWithData:self.receivedData];
}

-(void) reportError:(NSError*)error
{
    [self cancelTimeout];
    
    if([self.delegate respondsToSelector:@selector(webServiceRequest:failedWithError:)])
        [self.delegate webServiceRequest:self failedWithError:error];    
}

#pragma mark - NSURLConnectionDelegate
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self reportError:error];
        
    self.done = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // we received data. reset the timeout. 
    [self scheduleTimeout];
    
    @synchronized(self)
    {
        self.bytesReceived += data.length;
        
        if (self.targetFileURL) {        
            NSError* error = nil;

            if(nil == self.targetFileHandle)
            {
                
                NSString* path = [self.targetFileURL path];
                [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:[NSDictionary dictionaryWithObject:NSFileTypeRegular forKey:NSFileType]];
                
                self.targetFileHandle = [NSFileHandle fileHandleForWritingToURL:self.targetFileURL error:&error];
                
                if(nil == self.targetFileHandle)
                {

                    NSLog(@"Error opening file for streaming: %@", error); 

                    [self reportError:error];
                
                    self.done = YES;
                    [self cancel];
            
                    return;
                }
            }
            
           [self.targetFileHandle writeData:data];
        }
        
        else 
        {
            
            if (nil == self.receivedData) 
                self.receivedData = [[NSMutableData alloc] init];
               
            [self.receivedData appendData:data];
        }
        

        if(self.responseSize > 0)
        {
            float progress = self.bytesReceived / self.responseSize;
            
            if ([self.target respondsToSelector:@selector(setProgress:animated:)]) {
                [self.target setProgress:progress animated:YES];
            } else if ([self.target respondsToSelector:@selector(setProgress:)])  {
                [self.target setProgress:progress];
            }
        }
    }
    
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{    
    [self cancelTimeout];
    
    if ([self.delegate respondsToSelector:@selector(webServiceRequest:completedWithData:)]) {
        
        if(self.targetFileHandle)
        {
            [self.targetFileHandle closeFile];
            
            // ensure the expected file type is set to "File"
            self.expectedResultType = @"File";
            NSString* path = [self.targetFileURL path];
            NSData* data = [path dataUsingEncoding:NSUTF8StringEncoding];
            [self.delegate webServiceRequest:self completedWithData:data];
        }
        else {
            [self.delegate webServiceRequest:self completedWithData:self.receivedData];            
        }
    }
    
    self.done = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [self scheduleTimeout];
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        self.responseHeaders = [httpResponse allHeaderFields];
        self.responseSize = [httpResponse expectedContentLength];
    }
 
}

@end
