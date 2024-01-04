%{
#include "MediaFrameListenerBridge.h"
%}

%include "EventLoop.i"
%include "RTPIncomingMediaStream.i"
%include "RTPReceiver.i"
%include "MediaFrame.i"
%include "RTMPServerModule.i"

%nodefaultctor MediaFrameListenerBridge;
struct MediaFrameListenerBridge : 
	public RTPIncomingMediaStream,
	public RTPReceiver,
	public MediaFrameListener,
	public MediaFrameProducer
{
	MediaFrameListenerBridge(TimeService& timeService, int ssrc);

	QWORD numFrames;
	QWORD numPackets;
	QWORD numFramesDelta;
	QWORD numPacketsDelta;
	QWORD totalBytes;
	DWORD bitrate;
	DWORD minWaitedTime;
	DWORD maxWaitedTime;
	DWORD avgWaitedTime;
	WORD width;
	WORD height;
	QWORD iframes;
	QWORD iframesDelta;
	QWORD bframes;
	QWORD bframesDelta;
	QWORD pframes;
	QWORD pframesDelta;

	void Update();
	
	void Stop();

	//From MediaFrameProducer
	void AddMediaListener(const MediaFrameListenerShared& listener);
	void RemoveMediaListener(const MediaFrameListenerShared& listener);

	void SetTargetBitrateHint(uint32_t targetBitrateHint);

%extend 
{
	// Note: Extra const on right of pointer to let SWIG know this only wants a get accessor
	char const * const codec;

	void UpdateAsync(v8::Local<v8::Object> object)
	{
		auto persistent = std::make_shared<Persistent<v8::Object>>(object);
		self->UpdateAsync([=](std::chrono::milliseconds){
			RTMPServerModule::Async([=](){
				Nan::HandleScope scope;
				int i = 0;
				v8::Local<v8::Value> argv[0];
				//Call object method with arguments
				MakeCallback(persistent, "resolve", i, argv);
			});
		});
	}
}
};

%{
	char const * const MediaFrameListenerBridge_codec_get(MediaFrameListenerBridge* self)      { return GetNameForCodec(self->type, self->codec); }
%}

SHARED_PTR_BEGIN(MediaFrameListenerBridge)
{
	MediaFrameListenerBridgeShared(TimeService& timeService, int ssrc)
	{
		return new std::shared_ptr<MediaFrameListenerBridge>(new MediaFrameListenerBridge(timeService, ssrc));
	}
	SHARED_PTR_TO(RTPIncomingMediaStream)
	SHARED_PTR_TO(RTPReceiver)
	SHARED_PTR_TO(MediaFrameListener)
	SHARED_PTR_TO(MediaFrameProducer)
}
SHARED_PTR_END(MediaFrameListenerBridge)
