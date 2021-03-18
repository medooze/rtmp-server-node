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
#include <memory>
#include <nan.h>

using MediaFrameListener = MediaFrame::Listener;

template<typename T>
struct CopyablePersistentTraits {
public:
	typedef Nan::Persistent<T, CopyablePersistentTraits<T> > CopyablePersistent;
	static const bool kResetInDestructor = true;
	template<typename S, typename M>
	static inline void Copy(const Nan::Persistent<S, M> &source, CopyablePersistent *dest) {}
	template<typename S, typename M>
	static inline void Copy(const v8::Persistent<S, M>&, v8::Persistent<S, CopyablePersistentTraits<S> >*){}
};

template<typename T>
class NonCopyablePersistentTraits { 
public:
  typedef Nan::Persistent<T, NonCopyablePersistentTraits<T> > NonCopyablePersistent;
  static const bool kResetInDestructor = true;

  template<typename S, typename M>
  static void Copy(const Nan::Persistent<S, M> &source, NonCopyablePersistent *dest);

  template<typename O> static void Uncompilable();
};

template<typename T >
using Persistent = Nan::Persistent<T,NonCopyablePersistentTraits<T>>;


bool MakeCallback(const std::shared_ptr<Persistent<v8::Object>>& persistent, const char* name, int argc = 0, v8::Local<v8::Value>* argv = nullptr)
{
	Nan::HandleScope scope;
	//Ensure we have an object
	if (!persistent)
		return false;
	//Get a local reference
	v8::Local<v8::Object> local = Nan::New(*persistent);
	//Check it is not empty
	if (local.IsEmpty())
		return false;
	//Get event name
	auto method = Nan::New(name).ToLocalChecked();
	//Get attribute 
	auto attr = Nan::Get(local,method);
	//Check 
	if (attr.IsEmpty())
		return false;
	//Create callback function
	auto callback = Nan::To<v8::Function>(attr.ToLocalChecked());
	//Check 
	if (callback.IsEmpty())
		return false;
	//Call object method with arguments
	Nan::MakeCallback(local, callback.ToLocalChecked(), argc, argv);
	
	//Done 
	return true;
}
	
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

	~RTMPServerModule()
	{
		Terminate();
	}
	
	/*
	 * Async
	 *  Enqueus a function to the async queue and signals main thread to execute it
	 */
	static void Async(std::function<void()> func) 
	{
		//Lock
		mutex.Lock();
		//Check if not terminatd
		if (uv_is_active((uv_handle_t *)&async))
		{
			//Enqueue
			queue.push_back(func);
			//Signal main thread
			uv_async_send(&async);
		}
		//Unlock
		mutex.Unlock();
	}

	static void Initialize()
	{
		Log("-RTMPServerModule::Initialize\n");
		//Init async handler
		uv_async_init(uv_default_loop(), &async, async_cb_handler);
	}
	
	static void Terminate()
	{
		Log("-RTMPServerModule::Terminate\n");
		//Lock
		mutex.Lock();
		//empty queue
		queue.clear();
		//Close handle
		uv_close((uv_handle_t *)&async, NULL);
		//Unlock
		mutex.Unlock();
	}
	
	static void EnableLog(bool flag)
	{
		//Enable log
		Logger::EnableLog(flag);
	}
	
	static void EnableDebug(bool flag)
	{
		//Enable debug
		Logger::EnableDebug(flag);
	}
	
	static void EnableUltraDebug(bool flag)
	{
		//Enable debug
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
	IncomingStreamBridge(v8::Local<v8::Object> object) :
		audio(1),
		video(2),
		mutex(true)
	{
		//Store event callback object
		persistent = std::make_shared<Persistent<v8::Object>>(object);
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
		//Check if already stopped
		if (stopped)
			return;

		Log("-IncomingStreamBridge::Stop()\n");

		//We are stopped
		stopped = true;

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
		
		//Set current time
		frame->SetTime(now);
		
		//Run on thread
		loop.Async([=](...) {
			
			//Convert timestamp 
			uint64_t timestamp = frame->GetTimeStamp()*1000/frame->GetClockRate();
			
			//IF it is first
			if (!first)
			{
				//Get timestamp
				first = timestamp;
				//Get current time
				ini = now;
			}

			//Check when it has to be sent
			auto sched = ini + (timestamp - first);

			//Is this frame too late? (allow 200ms offset)
			if (sched + 200 < now)
			{
				/*Log("-Got late frame %s timestamp:%lu(%llu) time:%llu ini:%llu\n",
					frame->GetType() == MediaFrame::Video ? "VIDEO" : "AUDIO",
					frame->GetTimeStamp(),
					timestamp,
					frame->GetTime() - ini,
					ini
				);*/
				//Update timestamp for first
				first = timestamp;
				//Get current time
				ini = now;
				//Send now
				sched = now;
			}

			/*Log("-Frame %s scheduled in %lldms timestamp:%lu time:%llu rel:%llu first:%lu ini:%llu\n", 
				frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
				sched - now,
				frame->GetTimeStamp(),
				frame->GetTime()-ini,
				frame->GetTime()-first,
				first,
				ini
			 );*/
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
					RTMPServerModule::Async([=,cloned=persistent](){
						Nan::HandleScope scope;
						int i = 0;
						v8::Local<v8::Value> argv[1];
						//Create local args
						argv[i++] = Nan::New<v8::String>(config).ToLocalChecked();
						//Call object method with arguments
						MakeCallback(cloned, "onaacconfig", i, argv);
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
	std::shared_ptr<Persistent<v8::Object>> persistent;	
	std::multimap<uint64_t,std::unique_ptr<MediaFrame>> queue;
	EventLoop loop;
	Timer::shared dispatch;
		
	uint64_t first = (uint64_t)-1;
	uint64_t ini = (uint64_t)-1;
	bool stopped = false;
};

class RTMPNetStreamImpl : 
	public RTMPNetStream
{
public:
	RTMPNetStreamImpl(DWORD id,Listener *listener) : RTMPNetStream(id,listener) {}
	
	void SetListener(v8::Local<v8::Object> object)
	{
		
		//Lock
		mutex.Lock();
		//Store event callback object
		persistent = std::make_shared<Persistent<v8::Object>>(object);
		//Unlock
		mutex.Unlock();
		
		//Launc pending commands
		for (auto& cmd : pending)
			//Proccess them now
			ProcessCommandMessage(cmd.get());
		//Clear pending
		pending.clear();
	}
	
	void ResetListener()
	{
		//Lock
		ScopedLock scope(mutex);
		//Reset js listener object
		persistent.reset();
	}
	
	virtual void ProcessCommandMessage(RTMPCommandMessage* cmd)
	{
		//Lock
		ScopedLock scope(mutex);
		
		if (!persistent || persistent->IsEmpty())
		{
			//Add command to pending until the listener is set
			pending.emplace_back(cmd->Clone());
			//Do nothing yet
			return;
		}
		
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
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			int i = 0;
			v8::Local<v8::Value> argv[extras.size()+2];
			
			//Create local args
			argv[i++] = Nan::New<v8::String>(name).ToLocalChecked();
			argv[i++] = toJson(params); 
			delete(params);
			for (auto& extra : extras)
			{
				argv[i++] = toJson(extra);
				delete(extra);
			}
			//Call object method with arguments
			MakeCallback(cloned, "oncmd", i, argv);
		});
	}
	
	void SendStatus(v8::Local<v8::Object> code,v8::Local<v8::Object> level,v8::Local<v8::Object> desc)
	{

		UTF8Parser parserCode;
		UTF8Parser parserLevel;
		UTF8Parser parserDesc;
		parserCode.SetString(*Nan::Utf8String(code));
		parserLevel.SetString(*Nan::Utf8String(level));
		parserDesc.SetString(*Nan::Utf8String(desc));
		fireOnNetStreamStatus({parserCode.GetWChar(),parserLevel.GetWChar()},parserDesc.GetWChar());
		
	}
	
	void Stop()
	{
		//Lock
		ScopedLock scope(mutex);
		
		Log("-RTMPNetStreamImpl::Stop() [streamId:%d]\n",id);
		
		RTMPMediaStream::RemoveAllMediaListeners();
		listener = nullptr;
		
		if (!persistent || persistent->IsEmpty())
			//Do nothing
			return;
		
		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//Call object method with arguments
			MakeCallback(cloned, "onstopped");
		});
		
		
	}
private:
	Mutex mutex;
	std::shared_ptr<Persistent<v8::Object>> persistent;	
	std::vector<std::unique_ptr<RTMPCommandMessage>> pending;
};


class RTMPNetConnectionImpl :
	public RTMPNetConnection
{
public:	
	RTMPNetConnectionImpl(Listener *listener,std::function<void(bool)> accept) :
		accept(accept)
	{
		//Add us as listeners
		AddListener(listener);
	}

	void Accept(v8::Local<v8::Object> object)
	{
		//Store event callback object
		persistent = std::make_shared<Persistent<v8::Object>>(object);
		//Accept connection
		accept(true);
	}
	
	void Reject()
	{
		//Reject connection
		accept(false);
	}

	virtual RTMPNetStream::shared CreateStream(DWORD streamId,DWORD audioCaps,DWORD videoCaps,RTMPNetStream::Listener *listener) override
	{
		Log("-RTMPNetConnectionImpl::CreateStream() [streamId:%d]\n",streamId);
		
		//Create connection
		auto stream = std::make_shared<RTMPNetStreamImpl>(streamId,listener);
		
		//Register stream
		RegisterStream(stream);
		
		//Check we have a callback object
		if (!persistent || persistent->IsEmpty())
			//Do nothing
			return stream;
		
		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//We create a new shared pointer
			auto shared = new std::shared_ptr<RTMPNetStream>(stream);
			//Create local args
			v8::Local<v8::Value> argv[1] = {
				SWIG_NewPointerObj(SWIG_as_voidptr(shared), SWIGTYPE_p_RTMPNetStreamShared,SWIG_POINTER_OWN)
			};
			//Call object method with arguments
			MakeCallback(cloned, "onstream", 1, argv);
		});
		
		return stream;
	}

	virtual void DeleteStream(const RTMPNetStream::shared& stream) override
	{
		Log("-RTMPNetConnectionImpl::CreateStream() [streamId:%d]\n",stream->GetStreamId());
		
		//Cast
		auto impl = std::static_pointer_cast<RTMPNetStreamImpl>(stream);
		//Signael stop event
		impl->Stop();
		//Unregister stream
		UnRegisterStream(stream);
	}
	
	virtual void Disconnect()
	{
		//Ensure no callback is fired
		persistent.reset();
		//Disconnect
		RTMPNetConnection::Disconnect();
	}
	
	virtual void Disconnected() 
	{
		RTMPNetConnection::Disconnected();
		
		if (!persistent || persistent->IsEmpty())
			//Do nothing
			return;
	
		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//Call object method with arguments
			MakeCallback(cloned, "ondisconnect");
		});
	}
private:
	std::function<void(bool)> accept;
	std::shared_ptr<Persistent<v8::Object>> persistent;	
};

class RTMPApplicationImpl : 
	public RTMPApplication
{
public:
	RTMPApplicationImpl(v8::Local<v8::Object> object)
	{
		persistent = std::make_shared<Persistent<v8::Object>>(object);
	}

	virtual ~RTMPApplicationImpl() = default;

	virtual RTMPNetConnection* Connect(const std::wstring& appName,RTMPNetConnection::Listener *listener,std::function<void(bool)> accept) override
	{
		//Create connection
		auto connection = new RTMPNetConnectionImpl(listener,accept);
		
		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			
			//Create local args
			UTF8Parser parser(appName);
			auto str	= Nan::New<v8::String>(parser.GetUTF8String());
			auto object	= SWIG_NewPointerObj(SWIG_as_voidptr(connection), SWIGTYPE_p_RTMPNetConnectionImpl,SWIG_POINTER_OWN);
			//Create arguments
			v8::Local<v8::Value> argv[2] = {
				str.ToLocalChecked(),
				object
			};
			
			//Call object method with arguments
			MakeCallback(cloned, "onconnect", 2, argv);
		});
		
		return connection;
	}
private:
	std::shared_ptr<Persistent<v8::Object>> persistent;	
};


class RTMPServerFacade : 
	public RTMPServer
{
public:	
	RTMPServerFacade(v8::Local<v8::Object> object)
	{
		persistent = std::make_shared<Persistent<v8::Object>>(object);
	}
	void Start(int port)
	{
		Init(port);
	}

	void AddApplication(v8::Local<v8::Object> name,RTMPApplicationImpl *app)
	{
		UTF8Parser parser;
		parser.SetString(*Nan::Utf8String(name));
		RTMPServer::AddApplication(parser.GetWChar(),app);
	}
	
	void Stop()
	{
		End();
	}
private:
	std::shared_ptr<Persistent<v8::Object>> persistent;	
};


%}
%include "stdint.i"
%include "std_vector.i"
%include "../media-server/include/config.h"

%typemap(in) v8::Local<v8::Object> {
	$1 = v8::Local<v8::Object>::Cast($input);
}

class RTMPApplicationImpl
{
public:
	RTMPApplicationImpl(v8::Local<v8::Object> object);
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

%nodefaultctor MediaFrameListener;
%nodefaultdtor MediaFrameListener;
struct MediaFrameListener
{
};
	
%nodefaultctor MediaFrameListenerBridge;
struct MediaFrameListenerBridge : public RTPIncomingMediaStream
{
	DWORD numFrames;
	DWORD numPackets;
	DWORD numFramesDelta;
	DWORD numPacketsDelta;
	DWORD totalBytes;
	DWORD bitrate;
	DWORD minWaitedTime;
	DWORD maxWaitedTime;
	DWORD avgWaitedTime;
	void Update();
	
	void AddMediaListener(MediaFrameListener* listener);
	void RemoveMediaListener(MediaFrameListener* listener);
};

class IncomingStreamBridge : public RTMPMediaStreamListener
{
public:
	IncomingStreamBridge(v8::Local<v8::Object> object);
	MediaFrameListenerBridge* GetAudio();
	MediaFrameListenerBridge* GetVideo();
	RTPReceiver*		GetReceiver();
	void Stop();
};

%nodefaultctor RTMPNetStreamImpl;
class RTMPNetStreamImpl
{
public:
	void SetListener(v8::Local<v8::Object> object);
	void ResetListener();
	void SendStatus(v8::Local<v8::Object> status,v8::Local<v8::Object> level,v8::Local<v8::Object> desc);
	void AddMediaListener(RTMPMediaStreamListener* listener);
	void RemoveMediaListener(RTMPMediaStreamListener* listener);
	void Stop();
};

%{
using RTMPNetStreamShared =  std::shared_ptr<RTMPNetStream>;
%}
%nodefaultctor RTMPNetStreamShared;
struct RTMPNetStreamShared
{
	RTMPNetStreamImpl* get();
};

%nodefaultctor RTMPNetConnectionImpl;
class RTMPNetConnectionImpl
{
public:
	void Accept(v8::Local<v8::Object> object);
	void Reject();
	void Disconnect();
};

class RTMPServerFacade
{
public:	
	RTMPServerFacade(v8::Local<v8::Object> object);
	void Start(int port);
	void AddApplication(v8::Local<v8::Object> name,RTMPApplicationImpl *app);
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
