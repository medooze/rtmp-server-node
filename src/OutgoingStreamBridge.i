%{
#include "MediaFrameListenerBridge.h"

class OutgoingStreamBridge : 
	public RTMPMediaStream,
	public MediaFrame::Listener
{
public:
	OutgoingStreamBridge(DWORD streamId, RTMPMediaStream::Listener* listener) :
		RTMPMediaStream(streamId)
	{
		AddMediaListener(listener);
		SendStreamBegin();
	}

	// MediaFrame::Listener interface
	virtual void onMediaFrame(const MediaFrame& frame) override { onMediaFrame(0, frame); };
	virtual void onMediaFrame(DWORD ssrc, const MediaFrame& frame)
	{
		//Get timestamp at 1khz
		auto timestamp = frame.GetTimestamp()*1000/frame.GetClockRate();

		switch(frame.GetType())
		{
			case MediaFrame::Audio:
			{
				//Get audio frame
				AudioFrame& audio = (AudioFrame&)frame;
				//Create rtmp frame
				RTMPAudioFrame frame(timestamp,audio.GetLength());
				//Check codec
				switch(audio.GetCodec())
				{
					case AudioCodec::AAC:
					{
						//Set aac codec
						frame.SetAudioCodec(RTMPAudioFrame::AAC);
						//Set type
						frame.SetAACPacketType(RTMPAudioFrame::AACRaw);
						//Set Data
						frame.SetAudioFrame(audio.GetData(),audio.GetLength());

						//Check if we need to send the aac config
						if (!sentAACSpecificConfig && audio.HasCodecConfig())
						{
							//Get aac descriptor
							AACSpecificConfig desc;
							if (desc.Decode(audio.GetCodecConfigData(), audio.GetCodecConfigSize()))
							{
								//Create the fraame
								RTMPAudioFrame fdesc(timestamp, desc);
								//Play it
								SendMediaFrame(&fdesc);
								//Sent
								sentAACSpecificConfig = true;
							}
						}
						break;
					}
					default:
						//Log
						Warning("-OutgoingStreamBridge::onMediaFrame() Audio codec not supported\n");
						//Not supported
						return;
				}
				//Send it
				SendMediaFrame(&frame);
				break;
			}
			case MediaFrame::Video:
			{
				//Get video frame
				VideoFrame& video = (VideoFrame&)frame;

				//Create rtmp frame
				RTMPVideoFrame frame(timestamp,video.GetLength());
				//Check codec
				switch(video.GetCodec())
				{
					case VideoCodec::H264:
					{
						//Set Codec
						frame.SetVideoCodec(RTMPVideoFrame::AVC);
						//If it is intra
						if (video.IsIntra())
						{
							//Set type
							frame.SetFrameType(RTMPVideoFrame::INTRA);
							//If we have one
							if (video.HasCodecConfig())
							{
								//Get AVC descroptor
								AVCDescriptor desc;
								if (desc.Parse(video.GetCodecConfigData(), video.GetCodecConfigSize()))
								{
									//Create the fraame
									RTMPVideoFrame fdesc(timestamp, desc);
									//Play it
									SendMediaFrame(&fdesc);
								}
							}
						} else {
							//Set type
							frame.SetFrameType(RTMPVideoFrame::INTER);
						}
						//Set NALU type
						frame.SetAVCType(RTMPVideoFrame::AVCNALU);
						//Set no delay
						frame.SetAVCTS(0);
						//Set Data
						frame.SetVideoFrame(video.GetData(),video.GetLength());
						break;
					}
					default:
						//Log
						Warning("-OutgoingStreamBridge::onMediaFrame() Video codec not supported\n");
						//Not supported
						return;
				}
				//Send it
				SendMediaFrame(&frame);
				break;
			}
			default:
				//Log
				Warning("-OutgoingStreamBridge::onMediaFrame() Media type not supported\n");
				//Ignore
				return;
		}
	}

	void Stop()
	{
		SendStreamEnd();
		Reset();
		RemoveAllMediaListeners();
	}
private:
	bool sentAACSpecificConfig = false;
};

%}


class OutgoingStreamBridge
{
public:
	OutgoingStreamBridge(DWORD streamId, RTMPMediaStreamListener* listener);
	DWORD GetStreamId() const;
	DWORD GetRTT() const;
	void Stop();
};

SHARED_PTR_BEGIN(OutgoingStreamBridge)
{
	OutgoingStreamBridgeShared(DWORD streamId, RTMPMediaStreamListener* listener)
	{
		return new std::shared_ptr<OutgoingStreamBridge>(new OutgoingStreamBridge(streamId, listener));
	}
	SHARED_PTR_TO(MediaFrameListener)
}
SHARED_PTR_END(OutgoingStreamBridge)
