%module medooze
%{
#include "rtp.h"
#include "rtmp/amf.h"
#include "rtmp/rtmp.h"
#include "rtmp/rtmpchunk.h"
#include "rtmp/rtmpmessage.h"
#include "rtmp/rtmpstream.h"
#include "rtmp/rtmpapplication.h"
#include "rtmp/rtmpclientconnection.h"
#include "rtmp/rtmpserver.h"
#include "rtmp/rtmpconnection.h"
#include "rtmp/rtmphandshake.h"
#include "rtmp/rtmpnetconnection.h"
#include "rtmp/rtmppacketizer.h"
#include "MediaFrameListenerBridge.h"
#include "EventLoop.h"
	

#include <string>
#include <list>
#include <map>
#include <functional>
#include <nan.h>
	
template<typename T>
struct CopyablePersistentTraits {
	typedef Nan::Persistent<T, CopyablePersistentTraits<T> > CopyablePersistent;
	static const bool kResetInDestructor = true;
	template<typename S, typename M>
	static inline void Copy(const Nan::Persistent<S, M> &source, CopyablePersistent *dest) {}
	template<typename S, typename M>
	static inline void Copy(const v8::Persistent<S, M>&, v8::Persistent<S, CopyablePersistentTraits<S> >*){}
};

template<typename T >
using Persistent = Nan::Persistent<T,CopyablePersistentTraits<T>>;

	
v8::Local<v8::Value> toJson(AMFData* data)
{
	Nan::EscapableHandleScope scope;
	v8::Local<v8::Value> val = Nan::Null();
	
	if (!data)
		return scope.Escape(val);
	
	switch (data->GetType())
	{
		case AMFData::Number:
		{
			AMFNumber* number = (AMFNumber*)data;
			val = Nan::New<v8::Number>(number->GetNumber());
			break;
		}
		case AMFData::Boolean:
		{
			AMFBoolean* boolean = (AMFBoolean*)data;
			val = Nan::New<v8::Boolean>(boolean->GetBoolean());
			break;
		}
		case AMFData::String:
		{
			AMFString* string = (AMFString*)data;
			val = Nan::New<v8::String>(string->GetUTF8String()).ToLocalChecked();
			break;
		}
		case AMFData::Object:
		{
			AMFObject* object = (AMFObject*)data;
			auto& elements = object->GetProperties();
			val = Nan::New<v8::Object>();
			for (auto& el : elements)
			{	
				UTF8Parser parser(el.first);
				auto key = Nan::New<v8::String>(parser.GetUTF8String()).ToLocalChecked();
				auto elm = toJson(el.second);
				Nan::Set(Nan::To<v8::Object>(val).ToLocalChecked(), key, elm);
			}
			break;
		}
		case AMFData::EcmaArray:
		{
			AMFEcmaArray* array = (AMFEcmaArray*)data;
			auto& elements = array->GetElements();
			val = Nan::New<v8::Array>(array->GetLength());
			for (auto& el : elements)
			{	
				UTF8Parser parser(el.first);
				auto key = Nan::New<v8::String>(parser.GetUTF8String()).ToLocalChecked();
				auto elm = toJson(el.second);
				Nan::Set(Nan::To<v8::Object>(val).ToLocalChecked(), key, elm);
			}
			break;
		}
		case AMFData::StrictArray:
		{
			AMFStrictArray* array = (AMFStrictArray*)data;
			auto elements = array->GetElements();
			val = Nan::New<v8::Array>(array->GetLength());
			for (uint32_t i=0;i<array->GetLength();++i)
			{
				auto key = Nan::New<v8::Uint32>(i);
				auto elm = toJson(elements[i]);
				Nan::Set(Nan::To<v8::Object>(val).ToLocalChecked(), key, elm);
			}
			break;
		}
		case AMFData::Date:
		{
			break;
		}
		case AMFData::LongString:
		{
			AMFLongString* string = (AMFLongString*)data;
			val = Nan::New<v8::String>(string->GetUTF8String()).ToLocalChecked();
			break;
		}
		case AMFData::MovieClip:
		case AMFData::Null:
		case AMFData::Undefined:
		case AMFData::Reference:
		case AMFData::Unsupported:
		case AMFData::RecordSet:
		case AMFData::XmlDocument:
		case AMFData::TypedObject:
			//Not supported
			break;
	}
	return scope.Escape(val);
}

class RTMPServerModule
{
public:
	typedef std::list<v8::Local<v8::Value>> Arguments;
public:

	/*
	 * MakeCallback
	 *  Executes an object method async on the main node loop
	 */
	static void MakeCallback(v8::Handle<v8::Object> object, const char* method,Arguments& arguments)
	{
		// Create a copiable persistent
		Persistent<v8::Object>* persistent = new Persistent<v8::Object>(object);
		
		std::list<Persistent<v8::Value>*> pargs;
		for (auto it = arguments.begin(); it!= arguments.end(); ++it)
			pargs.push_back(new Persistent<v8::Value>(*it));
			
		
		//Run function on main node thread
		RTMPServerModule::Async([=,persistent = persistent](){
			Nan::HandleScope scope;
			int i = 0;
			v8::Local<v8::Value> argv2[pargs.size()];
			
			//Create local args
			for (auto it = pargs.begin(); it!= pargs.end(); ++it)
				argv2[i++] = Nan::New(*(*it));
			
			//Get a local reference
			v8::Local<v8::Object> local = Nan::New(*persistent);
			//Create callback function from object
			v8::Local<v8::Function> callback = v8::Local<v8::Function>::Cast(local->Get(Nan::New(method).ToLocalChecked()));
			//Call object method with arguments
			Nan::MakeCallback(local, callback, i, argv2);
			//Release object
			delete(persistent);
			//Release args
			//TODO
		});
		
	}
	
	/*
	 * MakeCallback
	 *  Executes object "emit" method async on the main node loop
	 */
	static void Emit(v8::Handle<v8::Object> object,Arguments& arguments)
	{
		RTMPServerModule::MakeCallback(object,"emit",arguments);
	}

	/*
	 * Async
	 *  Enqueus a function to the async queue and signals main thread to execute it
	 */
	static void Async(std::function<void()> func) 
	{
		//Lock
		mutex.Lock();
		//Enqueue
		queue.push_back(func);
		//Unlock
		mutex.Unlock();
		//Signal main thread
		uv_async_send(&async);
	}

	static void Initialize()
	{
		//Init async handler
		uv_async_init(uv_default_loop(), &async, async_cb_handler);
	}
	
	static void Terminate()
	{
		uv_close((uv_handle_t *)&async, NULL);
	}
	
	static void EnableLog(bool flag)
	{
		//Enable log
		Log("-EnableLog [%d]\n",flag);
		Logger::EnableLog(flag);
		Log("-EnableLog [%d]\n",flag);
	}
	
	static void EnableDebug(bool flag)
	{
		//Enable debug
		Log("-EnableDebug [%d]\n",flag);
		Logger::EnableDebug(flag);
	}
	
	static void EnableUltraDebug(bool flag)
	{
		//Enable debug
		Log("-EnableUltraDebug [%d]\n",flag);
		Logger::EnableUltraDebug(flag);
	}
	
	static void async_cb_handler(uv_async_t *handle)
	{
		//Lock
		mutex.Lock();
		//Get all
		while(!queue.empty())
		{
			//Get from queue
			auto func = queue.front();
			//Remove from queue
			queue.pop_front();
			//Unlock
			mutex.Unlock();
			//Execute async function
			func();
			//Lock
			mutex.Lock();
		}
		//Unlock
		mutex.Unlock();
	}
	
	
private:
	//http://stackoverflow.com/questions/31207454/v8-multithreaded-function
	static uv_async_t  async;
	static Mutex mutex;
	static std::list<std::function<void()>> queue;
};


//Static initializaion
uv_async_t RTMPServerModule::async;
Mutex RTMPServerModule::mutex;
std::list<std::function<void()>>  RTMPServerModule::queue;

class IncomingStreamBridge : 
	public RTMPMediaStream::Listener,
	public RTPReceiver
{
public:
	IncomingStreamBridge(v8::Handle<v8::Object> object) :
		audio(1),
		video(2),
		mutex(true)
	{
		//Store event callback object
		persistent.Reset(object);
		//Start time service
		loop.Start(-1);
		
		//Create dispatch timer
		dispatch = loop.CreateTimer([this](std::chrono::milliseconds now){
			
			//Iterate over the enqueued packets
			for(auto it = queue.begin(); it!=queue.end(); it = queue.erase(it))
			{
				//Get time and frame
				auto ts	    = std::chrono::milliseconds(it->first);
				auto& frame = it->second;
				
				//If not yet it's time
				if (ts > now)
				{
					//Log("-ReDispatching in %llums size=%d\n",(ts-now).count());
					//Schedule timer for later
					dispatch->Again(ts-now);
					//Done
					break;
				}
				//Log("-Dispatched from %llums size=%d\n",it->first, queue.size());
				//Check type
				if (frame->GetType()==MediaFrame::Audio)
					//Dispatch audio
					audio.onMediaFrame(*frame);
				else
					//Dispatch video
					video.onMediaFrame(*frame);
			}
		});
		
	}
		
	virtual ~IncomingStreamBridge()
	{
		Stop();
	}
	
	//Interface
	virtual void onAttached(RTMPMediaStream *stream)
	{
		//Log("-IncomingStreamBridge::onAttached() [streamId:%d]\n",stream->GetStreamId());
		
		ScopedLock scope(mutex);
		
		//Reset audio and video streasm
		audio.Reset();
		video.Reset();
		
		//Check if attached to another stream
		if (attached)
			//Remove ourself as listeners
			attached->RemoveMediaListener(this);
		//Store new one
		attached = stream;
	};
	
	virtual void onDetached(RTMPMediaStream *stream)
	{
		ScopedLock scope(mutex);
		
		//Log("-IncomingStreamBridge::onDetached() [streamId:%d]\n",stream->GetStreamId());
		
		//Detach if joined
		if (attached && attached!=stream)
			//Remove ourself as listeners
			attached->RemoveMediaListener(this);
		//Detach
		attached = nullptr;
	}

	void Stop()
	{
		//Cancel timer
		dispatch->Cancel();
		
		ScopedLock scope(mutex);
		
		//Detach if joined
		if (attached)
			//Remove ourself as listeners
			attached->RemoveMediaListener(this);
		//Detach it anyway
		attached = nullptr;
		
		//Stop thread
		loop.Stop();
	}
	
	void Enqueue(MediaFrame* frame)
	{
		//Get current time
		uint64_t now = getTimeMS();
		
		//Run on thread
		loop.Async([=](...) {
			
			//IF it is first
			if (!first)
			{
				//Get timestamp
				first = frame->GetTimeStamp();
				//Get current time
				ini = now;
			}

			//Check when it has to be sent
			auto sched = ini + (frame->GetTimeStamp() - first);
			
			//Is this frame late?
			if (sched < now)
			{
				//Update timestamp for first
				first = frame->GetTimeStamp();
				//Get current time
				ini = now;
				//Send now
				sched = now;
			}
			//Log("-Frame scheduled for diff:%lld time:%lu sched:%llu first:%lu ini:%llu\n",sched - now,frame->GetTimeStamp(),sched, first, ini);
			//Enqueue
			queue.emplace(sched,frame);
			
			//If queue was empty
			if (queue.size()==1)
			{
				//Log("-Dispatching in %llums size=%u\n",sched > now ? sched - now : 0, queue.size());
				//Schedule timer for later
				dispatch->Again(std::chrono::milliseconds(sched > now ? sched - now : 0));
			}		
		});
	}
	
	virtual void onMediaFrame(DWORD id,RTMPMediaFrame *frame)
	{
		//Depending on the type
		switch (frame->GetType())
		{
			case RTMPMediaFrame::Video:
			{
				//Create rtp packets
				auto videoFrame = avcPacketizer.AddFrame((RTMPVideoFrame*)frame);
				//IF got one
				if (videoFrame)
					//Push it
					Enqueue(videoFrame.release());
				break;
			}
			case RTMPMediaFrame::Audio:
			{
				//Check if it is the aac config
				if (((RTMPAudioFrame*)frame)->GetAudioCodec()==RTMPAudioFrame::AAC && ((RTMPAudioFrame*)frame)->GetAACPacketType()==RTMPAudioFrame::AACSequenceHeader)
				{
					//Create condig
					char aux[3];
					std::string config;
					
					//Encode config
					for (size_t i=0; i<frame->GetMediaSize();++i)
					{
						//Convert to hex
						snprintf(aux, 3, "%.2x", frame->GetMediaData()[i]);
						//Append
						config += aux;
					}
					
					//Run function on main node thread
					RTMPServerModule::Async([=,persistent = persistent](){
						Nan::HandleScope scope;
						//Get a local reference
						v8::Local<v8::Object> local = Nan::New(persistent);
						//Create arguments
						v8::Local<v8::Value> argvs[1];
						uint32_t len = 0;

						argvs[len++] = Nan::New<v8::String>(config).ToLocalChecked();
						//Create callback function from object
						v8::Local<v8::Function> callback = v8::Local<v8::Function>::Cast(local->Get(Nan::New("onaacconfig").ToLocalChecked()));
						//Call object method with arguments
						Nan::MakeCallback(local, callback, len, argvs);
					});
				}

				//Create rtp packets
				auto audioFrame = aacPacketizer.AddFrame((RTMPAudioFrame*)frame);
				//IF got one
				if (audioFrame)
					//Push it
					Enqueue(audioFrame.release());
				break;
			}
		}
	}
	virtual void onMetaData(DWORD id,RTMPMetaData *meta) {};
	virtual void onCommand(DWORD id,const wchar_t *name,AMFData* obj) {};
	virtual void onStreamBegin(DWORD id)
	{
		Log("-IncomingStreamBridge::onStreamBegin() [streamId:%d]\n",id);
	};
	virtual void onStreamEnd(DWORD id)
	{
		Log("-IncomingStreamBridge::onStreamEnd() [streamId:%d]\n",id);
	};
	virtual void onStreamReset(DWORD id)
	{
		Log("-IncomingStreamBridge::onStreamReset() [streamId:%d]\n",id);
	};
	
	virtual int SendPLI(DWORD ssrc)
	{
		//oh, not possible on rtmp
		return 1;
	}
	
	MediaFrameListenerBridge* GetAudio()	{ return &audio; }
	MediaFrameListenerBridge* GetVideo()	{ return &video; }
	RTPReceiver*		GetReceiver()	{ return this; }
	
private:
	
	RTMPAVCPacketizer avcPacketizer;
	RTMPAACPacketizer aacPacketizer;
	MediaFrameListenerBridge audio;
	MediaFrameListenerBridge video;
	Mutex mutex;
	RTMPMediaStream *attached = nullptr;
	Persistent<v8::Object> persistent;	
	std::multimap<uint64_t,std::unique_ptr<MediaFrame>> queue;
	EventLoop loop;
	Timer::shared dispatch;
		
	uint64_t first = 0;
	uint64_t ini = 0;
};

class RTMPNetStreamImpl : 
	public RTMPNetStream
{
public:
	RTMPNetStreamImpl(DWORD id,Listener *listener) : RTMPNetStream(id,listener) {}
	
	void SetListener(v8::Handle<v8::Object> object)
	{
		//Store event callback object
		persistent.Reset(object);
	}
	
	virtual void ProcessCommandMessage(RTMPCommandMessage* cmd)
	{
		//Get cmd name params and extra data
		std::string name = cmd->GetNameUTF8();
		
		AMFData* params = cmd->HasParams() ? cmd->GetParams()->Clone() : nullptr;
		std::vector<AMFData*> extras;
		for (size_t i=0;i<cmd->GetExtraLength();++i)
		{
			auto extra = cmd->GetExtra(i);
			extras.push_back(extra ? extra->Clone() : nullptr);
		}
		//Run function on main node thread
		RTMPServerModule::Async([=,persistent = persistent](){
			Nan::HandleScope scope;
			//Get a local reference
			v8::Local<v8::Object> local = Nan::New(persistent);
			//Create arguments
			v8::Local<v8::Value> argvs[extras.size()+2];
			uint32_t len = 0;
			
			argvs[len++] = Nan::New<v8::String>(name).ToLocalChecked();
			argvs[len++] = toJson(params); 
			delete(params);
			for (auto& extra : extras)
			{
				argvs[len++] = toJson(extra);
				delete(extra);
			}
		
			//Create callback function from object
			v8::Local<v8::Function> callback = v8::Local<v8::Function>::Cast(local->Get(Nan::New("oncmd").ToLocalChecked()));
			//Call object method with arguments
			Nan::MakeCallback(local, callback, len, argvs);
		});
	}
	
	void SendStatus(v8::Handle<v8::Object> code,v8::Handle<v8::Object> level,v8::Handle<v8::Object> desc)
	{
		UTF8Parser parserCode;
		UTF8Parser parserLevel;
		UTF8Parser parserDesc;
		parserCode.SetString(*v8::String::Utf8Value(code.As<v8::String>()));
		parserLevel.SetString(*v8::String::Utf8Value(level.As<v8::String>()));
		parserDesc.SetString(*v8::String::Utf8Value(desc.As<v8::String>()));
		fireOnNetStreamStatus({parserCode.GetWChar(),parserLevel.GetWChar()},parserDesc.GetWChar());
		
	}
	
	void Stop()
	{
		Log("-RTMPNetStreamImpl::Stop() [streamId:%d]\n",id);
		
		//Run function on main node thread
		RTMPServerModule::Async([=,persistent = persistent](){
			Nan::HandleScope scope;
			//Get a local reference
			v8::Local<v8::Object> local = Nan::New(persistent);
			//Create arguments
			v8::Local<v8::Value> argv0[0] = {};
			//Create callback function from object
			v8::Local<v8::Function> callback = v8::Local<v8::Function>::Cast(local->Get(Nan::New("onstopped").ToLocalChecked()));
			//Call object method with arguments
			Nan::MakeCallback(local, callback, 0, argv0);
		});
		
		RTMPMediaStream::RemoveAllMediaListeners();
		listener = nullptr;
	}
private:
	Persistent<v8::Object> persistent;	
};


class RTMPNetConnectionImpl :
	public RTMPNetConnection
{
public:	
	RTMPNetConnectionImpl(Listener *listener,std::function<void(bool)> accept) :
		accept(accept)
	{
	}

	void Accept(v8::Handle<v8::Object> object)
	{
		//Store event callback object
		persistent.Reset(object);
		//Accept connection
		accept(true);
	}
	
	void Reject()
	{
		//Reject connection
		accept(false);
	}

	virtual RTMPNetStream* CreateStream(DWORD streamId,DWORD audioCaps,DWORD videoCaps,RTMPNetStream::Listener *listener) override
	{
		Log("-RTMPNetConnectionImpl::CreateStream() [streamId:%d]\n",streamId);
		
		//Create connection
		auto stream = new RTMPNetStreamImpl(streamId,listener);
		
		//Register stream
		RegisterStream(stream);
		
		//Run function on main node thread
		RTMPServerModule::Async([=,persistent = persistent](){
			Nan::HandleScope scope;
			//Create local args
			auto object	= SWIG_NewPointerObj(SWIG_as_voidptr(stream), SWIGTYPE_p_RTMPNetStreamImpl,SWIG_POINTER_OWN);
			//Create arguments
			v8::Local<v8::Value> argv1[1] = {object};
			//Get a local reference
			v8::Local<v8::Object> local = Nan::New(persistent);
			//Create callback function from object
			v8::Local<v8::Function> callback = v8::Local<v8::Function>::Cast(local->Get(Nan::New("onstream").ToLocalChecked()));
			//Call object method with arguments
			Nan::MakeCallback(local, callback, 1, argv1);
		});
		
		return stream;
	}

	virtual void DeleteStream(RTMPNetStream *stream) override
	{
		Log("-RTMPNetConnectionImpl::CreateStream() [streamId:%d]\n",stream->GetStreamId());
		
		//Cast
		auto impl = static_cast<RTMPNetStreamImpl*>(stream);
		//Signael stop event
		impl->Stop();
		//Unregister stream
		UnRegisterStream(stream);
	}
	
	void Disconnected() 
	{
		//Run function on main node thread
		RTMPServerModule::Async([=,persistent = persistent](){
			Nan::HandleScope scope;
			//Create arguments
			v8::Local<v8::Value> argv0[0] = {};
			//Get a local reference
			v8::Local<v8::Object> local = Nan::New(persistent);
			//Create callback function from object
			v8::Local<v8::Function> callback = v8::Local<v8::Function>::Cast(local->Get(Nan::New("ondisconnect").ToLocalChecked()));
			//Call object method with arguments
			Nan::MakeCallback(local, callback, 0, argv0);
		});
	}
private:
	std::function<void(bool)> accept;
	Persistent<v8::Object> persistent;	
};

class RTMPApplicationImpl : 
	public RTMPApplication
{
public:
	RTMPApplicationImpl(v8::Handle<v8::Object> object) :
		persistent(object)
	{
	}

	virtual ~RTMPApplicationImpl() = default;

	virtual RTMPNetConnection* Connect(const std::wstring& appName,RTMPNetConnection::Listener *listener,std::function<void(bool)> accept) override
	{
		//Create connection
		auto connection = new RTMPNetConnectionImpl(listener,accept);
		
		//Run function on main node thread
		RTMPServerModule::Async([=,persistent = persistent](){
			Nan::HandleScope scope;
			
			//Create local args
			UTF8Parser parser(appName);
			auto str	= Nan::New<v8::String>(parser.GetUTF8String());
			auto object	= SWIG_NewPointerObj(SWIG_as_voidptr(connection), SWIGTYPE_p_RTMPNetConnectionImpl,SWIG_POINTER_OWN);
			//Create arguments
			v8::Local<v8::Value> argv2[2] = {str.ToLocalChecked(),object};
			
			//Get a local reference
			v8::Local<v8::Object> local = Nan::New(persistent);
			//Create callback function from object
			v8::Local<v8::Function> callback = v8::Local<v8::Function>::Cast(local->Get(Nan::New("onconnect").ToLocalChecked()));
			//Call object method with arguments
			Nan::MakeCallback(local, callback, 2, argv2);
		});
		
		return connection;
	}
private:
	Persistent<v8::Object> persistent;	
};


class RTMPServerFacade : 
	public RTMPServer
{
public:	
	RTMPServerFacade(v8::Handle<v8::Object> object) :
		persistent(object)
	{
	}
	void Start(int port)
	{
		Init(port);
	}

	void AddApplication(v8::Handle<v8::Object> name,RTMPApplicationImpl *app)
	{
		UTF8Parser parser;
		parser.SetString(*v8::String::Utf8Value(name.As<v8::String>()));
		RTMPServer::AddApplication(parser.GetWChar(),app);
	}
	
	void Stop()
	{
		End();
	}
private:
	Persistent<v8::Object> persistent;	
};


%}
%include "stdint.i"
%include "std_vector.i"
%include "../media-server/include/config.h"

%typemap(in) v8::Handle<v8::Object> {
	$1 = v8::Handle<v8::Object>::Cast($input);
}

class RTMPApplicationImpl
{
public:
	RTMPApplicationImpl(v8::Handle<v8::Object> object);
};

%{
using RTMPMediaStreamListener =  RTMPMediaStream::Listener;
%}
%nodefaultctor RTMPMediaStreamListener;
struct RTMPMediaStreamListener
{
};


%nodefaultctor RTPIncomingMediaStream;
%nodefaultdtor RTPIncomingMediaStream;
struct RTPIncomingMediaStream
{
};
	
%nodefaultctor MediaFrameListenerBridge;
struct MediaFrameListenerBridge : public RTPIncomingMediaStream
{
	DWORD numFrames;
	DWORD numPackets;
	DWORD totalBytes;
	DWORD bitrate;
	void Update();
};

class IncomingStreamBridge : public RTMPMediaStreamListener
{
public:
	IncomingStreamBridge(v8::Handle<v8::Object> object);
	MediaFrameListenerBridge* GetAudio();
	MediaFrameListenerBridge* GetVideo();
	RTPReceiver*		GetReceiver();
	void Stop();
};

%nodefaultctor RTMPNetStreamImpl;
class RTMPNetStreamImpl
{
public:
	void SetListener(v8::Handle<v8::Object> object);
	void SendStatus(v8::Handle<v8::Object> status,v8::Handle<v8::Object> level,v8::Handle<v8::Object> desc);
	void AddMediaListener(RTMPMediaStreamListener* listener);
	void RemoveMediaListener(RTMPMediaStreamListener* listener);
};
	
%nodefaultctor RTMPNetConnectionImpl;
class RTMPNetConnectionImpl
{
public:
	void Accept(v8::Handle<v8::Object> object);
	void Reject();
	void Disconnect();
};

class RTMPServerFacade
{
public:	
	RTMPServerFacade(v8::Handle<v8::Object> object);
	void Start(int port);
	void AddApplication(v8::Handle<v8::Object> name,RTMPApplicationImpl *app);
	void Stop();
};


class RTMPServerModule
{
public:
	static void Initialize();
	static void Terminate();
	static void EnableLog(bool flag);
	static void EnableDebug(bool flag);
	static void EnableUltraDebug(bool flag);
};
