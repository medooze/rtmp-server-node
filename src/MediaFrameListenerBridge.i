%{
#include "MediaFrameListenerBridge.h"
%}

%include "EventLoop.i"
%include "RTPIncomingMediaStream.i"
%include "RTPReceiver.i"
%include "MediaFrame.i"

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
	void Update();
	
	void Stop();

	//From MediaFrameProducer
	void AddMediaListener(const MediaFrameListenerShared& listener);
	void RemoveMediaListener(const MediaFrameListenerShared& listener);
};

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