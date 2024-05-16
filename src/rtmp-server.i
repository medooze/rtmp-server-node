%module medooze
%{
#include "concurrentqueue.h"
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

%}

%include "stdint.i"
%include "std_vector.i"
%include "../media-server/include/config.h"

%typemap(in) v8::Local<v8::Object> {
	$1 = v8::Local<v8::Object>::Cast($input);
}

%include "shared_ptr.i"
%include "MediaFrame.i"
%include "MediaFrameListenerBridge.i"
%include "RTPIncomingMediaStream.i"
%include "RTMPMediaStream.i"


%include "RTMPServerModule.i"

%include "IncomingStreamBridge.i"
%include "OutgoingStreamBridge.i"
%include "RTMPApplicationImpl.i"
%include "RTMPNetStreamImpl.i"
%include "RTMPMediaStream.i"
%include "RTMPServerFacade.i"
%include "RTMPNetConnectionImpl.i"
%include "RTMPClientConnectionImpl.i"
%include "FrameDispatchCoordinator.i"
