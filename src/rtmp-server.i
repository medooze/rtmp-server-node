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

#include <string>
#include <list>
#include <functional>
#include <nan.h>
	
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
		Nan::Persistent<v8::Object>* persistent = new Nan::Persistent<v8::Object>(object);
		
		std::list<Nan::Persistent<v8::Value>*> pargs;
		for (auto it = arguments.begin(); it!= arguments.end(); ++it)
			pargs.push_back(new Nan::Persistent<v8::Value>(*it));
			
		
		//Run function on main node thread
		RTMPServerModule::Async([=](){
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
private:
	class IncomingMediaStreamBridge : public RTPIncomingMediaStream
	{
	public:
		IncomingMediaStreamBridge(DWORD ssrc) : ssrc(ssrc) {}
		virtual ~IncomingMediaStreamBridge() = default;
		virtual void AddListener(RTPIncomingMediaStream::Listener* listener)
		{
			Debug("-IncomingMediaStreamBridge::AddListener() [listener:%p]\n",listener);
			ScopedLock scope(mutex);
			listeners.insert(listener);
		}
		virtual void RemoveListener(RTPIncomingMediaStream::Listener* listener)
		{
			Debug("-IncomingMediaStreamBridge::RemoveListener() [listener:%p]\n",listener);
			ScopedLock scope(mutex);
			listeners.erase(listener);
		}
		void Dispatch(MediaFrame* frame)
		{
			//Check
			if (!frame || !frame->HasRtpPacketizationInfo())
				//Error
				return;
			
			//If we need to reset
			if (reset)
			{
				//Reset first paquet seq num and timestamp
				firstTimestamp = 0;
				//Store the last send ones
				baseTimestamp = lastTimestamp;
				//Reseted
				reset = false;
			}
			
			//Get info
			const MediaFrame::RtpPacketizationInfo& info = frame->GetRtpPacketizationInfo();

			DWORD codec = 0;
			BYTE *frameData = NULL;
			DWORD frameSize = 0;
			WORD  rate = 1;

			//Depending on the type
			switch(frame->GetType())
			{
				case MediaFrame::Audio:
				{
					//get audio frame
					AudioFrame * audio = (AudioFrame*)frame;
					//Get codec
					codec = audio->GetCodec();
					//Get data
					frameData = audio->GetData();
					//Get size
					frameSize = audio->GetLength();
					//Set default rate
					rate = 48;
					break;
				}
				case MediaFrame::Video:
				{
					//get Video frame
					VideoFrame * video = (VideoFrame*)frame;
					//Get codec
					codec = video->GetCodec();
					//Get data
					frameData = video->GetData();
					//Get size
					frameSize = video->GetLength();
					//Set default rate
					rate = 90;
					break;
				}
				
			}

			//Check if it the first received packet
			if (!firstTimestamp)
			{
				//If we have a time offest from last sent packet
				if (lastTime)
					//Calculate time difd and add to the last sent timestamp
					baseTimestamp = lastTimestamp + getTimeDiff(lastTime)/1000 + 1;
				//Get first timestamp
				firstTimestamp = frame->GetTimeStamp();
			}
			
			DWORD frameLength = 0;
			//Calculate total length
			for (int i=0;i<info.size();i++)
				//Get total length
				frameLength += info[i]->GetTotalLength();

			DWORD current = 0;
			
			//For each one
			for (int i=0;i<info.size();i++)
			{
				//Get packet
				MediaFrame::RtpPacketization* rtp = info[i];

				//Create rtp packet
				 auto packet = std::make_shared<RTPPacket>(frame->GetType(),codec);

				//Make sure it is enought length
				if (rtp->GetTotalLength()>packet->GetMaxMediaLength())
					//Error
					continue;
				//Set src
				packet->SetSSRC(ssrc);
				packet->SetExtSeqNum(extSeqNum++);
				//Set data
				packet->SetPayload(frameData+rtp->GetPos(),rtp->GetSize());
				//Add prefix
				packet->PrefixPayload(rtp->GetPrefixData(),rtp->GetPrefixLen());
				//Calculate timestamp
				lastTimestamp = baseTimestamp + (frame->GetTimeStamp()-firstTimestamp);
				//Set other values
				packet->SetTimestamp(lastTimestamp*rate);
				//Check
				if (i+1==info.size())
					//last
					packet->SetMark(true);
				else
					//No last
					packet->SetMark(false);
				//Calculate partial lenght
				current += rtp->GetPrefixLen()+rtp->GetSize();

				ScopedLock scope(mutex);
				for (auto listener : listeners)
					listener->onRTP(this,packet);
			}

			
		}
		virtual DWORD GetMediaSSRC() { return ssrc; }
		
		void Reset()
		{
			reset = true;
		}
	public:
		DWORD ssrc = 0;
		DWORD extSeqNum = 0;
		Mutex mutex;
		std::set<RTPIncomingMediaStream::Listener*> listeners;
		volatile bool reset	= false;
		DWORD firstTimestamp	= 0;
		QWORD baseTimestamp	= 0;
		QWORD lastTimestamp	= 0;
		QWORD lastTime		= 0;
	};
public:
	IncomingStreamBridge() :
		audio(1),
		video(2)
	{
		
	}
	virtual ~IncomingStreamBridge() = default;
	
	//Interface
	virtual void onAttached(RTMPMediaStream *stream)
	{
		ScopedLock scope(mutex);
		this->stream = stream;
		//Reset audio and video streasm
		audio.Reset();
		video.Reset();
	};
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
						//Send it
					video.Dispatch(videoFrame.release());
				break;
			}
			case RTMPMediaFrame::Audio:
			{
				//Create rtp packets
				auto audioFrame = aacPacketizer.AddFrame((RTMPAudioFrame*)frame);
				//IF got one
				if (audioFrame)
						//Send it
					audio.Dispatch(audioFrame.release());
				break;
			}
		}
	}
	virtual void onMetaData(DWORD id,RTMPMetaData *meta) {};
	virtual void onCommand(DWORD id,const wchar_t *name,AMFData* obj) {};
	virtual void onStreamBegin(DWORD id) {};
	virtual void onStreamEnd(DWORD id) {};
	virtual void onStreamReset(DWORD id) {};
	virtual void onDetached(RTMPMediaStream *stream)  {};
	
	virtual int SendPLI(DWORD ssrc)
	{
		//oh, not possible on rtmp
		return 1;
	}
	
	RTPIncomingMediaStream* GetAudio()	{ return &audio; }
	RTPIncomingMediaStream* GetVideo()	{ return &video; }
	RTPReceiver*		GetReceiver()	{ return this; }
	
private:
	
	RTMPAVCPacketizer avcPacketizer;
	RTMPAACPacketizer aacPacketizer;
	IncomingMediaStreamBridge audio;
	IncomingMediaStreamBridge video;
	Mutex mutex;
	RTMPMediaStream *stream = nullptr;
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
		RTMPServerModule::Async([=](){
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
		//Run function on main node thread
		RTMPServerModule::Async([=](){
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
	}
private:
	Nan::Persistent<v8::Object> persistent;	
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
		//Create connection
		auto stream = new RTMPNetStreamImpl(streamId,listener);
		
		//Register stream
		RegisterStream(stream);
		
		//Run function on main node thread
		RTMPServerModule::Async([=](){
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
		//Cast
		auto impl = static_cast<RTMPNetStreamImpl*>(stream);
		//Signael stop event
		impl->Stop();
		//Unregister stream
		UnRegisterStream(stream);
	}
	
private:
	std::function<void(bool)> accept;
	Nan::Persistent<v8::Object> persistent;	
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
		RTMPServerModule::Async([=](){
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
	Nan::Persistent<v8::Object> persistent;	
};


class RTMPServerFacade : 
	public RTMPServer
{
public:	
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
};

%}

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

class IncomingStreamBridge : public RTMPMediaStreamListener
{
public:
	IncomingStreamBridge();
	RTPIncomingMediaStream* GetAudio();
	RTPIncomingMediaStream* GetVideo();
	RTPReceiver*		GetReceiver();
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
