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
				//Make timestamp relative
				timestamp -= firstTimestamp;

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
						//16 bits
						frame.SetSamples16Bits(true);
						//Check if we need to send the aac config
						if (!gotAACSpecificConfig && audio.HasCodecConfig())
						{
							Dump(audio.GetCodecConfigData(), audio.GetCodecConfigSize());
							//Get aac descriptor
							if (aacSpecificConfig.Decode(audio.GetCodecConfigData(), audio.GetCodecConfigSize()))
							{
								//Got valid descriptor
								gotAACSpecificConfig = true;

								//If we have sent video before
								if (first)
								{
									//Send metadata
									GenerateMetadata(timestamp);
									//Create the frame
									RTMPAudioFrame fdesc(timestamp, aacSpecificConfig);
									//Play it
									SendMediaFrame(&fdesc);
								}
							}
						}
						if (gotAACSpecificConfig)
						{
							frame.SetStereo(aacSpecificConfig.GetChannels()==2);
						}
						break;
					}
					default:
						//Log
						Warning("-OutgoingStreamBridge::onMediaFrame() Audio codec not supported\n");
						//Not supported
						return;
				}
				//Wait for intra
				if (!first)
					return;
				//Send it
				SendMediaFrame(&frame);
				break;
			}
			case MediaFrame::Video:
			{
			
				//Get video frame
				VideoFrame& video = (VideoFrame&)frame;

				if (!first)
				{
					if (!video.IsIntra())
						return;
					//Got first frame after key frame
					first = true;
					firstTimestamp = timestamp;
				}
				
				//Make timestamp relative
				timestamp -= firstTimestamp;

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
							//Get video properties
							if (video.GetWidth())
								width = video.GetWidth();
							if (video.GetHeight())
								height = video.GetHeight();
							if (video.GetTargetFps())
								targetFps = video.GetTargetFps();
							if (video.GetTargetBitrate())
								targetBitrate = video.GetTargetBitrate();
							//Set type
							frame.SetFrameType(RTMPVideoFrame::INTRA);
							//If we have one
							if (!gotAVCDescriptor && video.HasCodecConfig())
							{
								//Get AVC descroptor
								if (avcDescriptor.Parse(video.GetCodecConfigData(), video.GetCodecConfigSize()))
								{
									//Got valid descriptor
									gotAVCDescriptor = true;
									//Send metadata
									GenerateMetadata(timestamp);
									//Create the fraame
									RTMPVideoFrame fdesc(timestamp, avcDescriptor);
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

	void GenerateMetadata(QWORD timestamp)
	{
		//Create metadata object
		RTMPMetaData *meta = new RTMPMetaData(timestamp);

		//Set cmd
		meta->AddParam(new AMFString(L"@setDataFrame"));

		//Set name
		meta->AddParam(new AMFString(L"onMetaData"));

		//Create properties string
		AMFEcmaArray *prop = new AMFEcmaArray();

		if (gotAACSpecificConfig)
		{
			
			prop->AddProperty(L"stereo"		, new AMFBoolean(aacSpecificConfig.GetChannels() == 2)	);	// Boolean Indicating stereo audio
			prop->AddProperty(L"audiochannels"	, (double)aacSpecificConfig.GetChannels()		);	
			prop->AddProperty(L"audiodatarate"	, 64.0							);	
			prop->AddProperty(L"audiodelay"		, 0.0							);	// Number Delay introduced by the audio codec in seconds
			prop->AddProperty(L"audiosamplerate"	, (double)aacSpecificConfig.GetRate()			);	// Number Frequency at which the audio stream is replayed
			prop->AddProperty(L"audiosamplesize"	, 160.0							);	// Number Resolution of a single audio sample
			prop->AddProperty(L"audiocodecid"	, (double)RTMPAudioFrame::AAC							);	// Number Audio codec ID used in the file (see E.4.3.1 for available CodecID values)
		}

		if (gotAVCDescriptor)
		{
			prop->AddProperty(L"videocodecid"	, (double)RTMPVideoFrame::AVC				);	// Number Video codec ID used in the file (see E.4.3.1 for available CodecID values)
			if (targetFps)
				prop->AddProperty(L"framerate"	, (double)targetFps.value()				);	// Number Number of frames per second
			if (height)
				prop->AddProperty(L"height"	, (double)height.value()				);	// Number Height of the video in pixels
			if (targetBitrate)
				prop->AddProperty(L"videodatarate"	, (double)targetBitrate.value()			);			// Number Video bit rate in kilobits per second
			if (width)
				prop->AddProperty(L"width"	, (double)width.value()					);	// Number Width of the video in pixels
			prop->AddProperty(L"canSeekToEnd"	,0.0							);	// Boolean Indicating the last video frame is a key frame
			prop->AddProperty(L"duration"		,0.0							);	// Number Total duration of the file in seconds
		}

				
		//Add param
		meta->AddParam(prop);

		//Send metadata
		SendMetaData(meta);
	}

	void Stop()
	{
		Reset();
		RemoveAllMediaListeners();
	}
private:
	AACSpecificConfig aacSpecificConfig;
	AVCDescriptor avcDescriptor;
	bool gotAACSpecificConfig = false;
	bool gotAVCDescriptor = false;
	bool first = false;
	QWORD firstTimestamp = 0;
	std::optional<uint32_t> width;
	std::optional<uint32_t> height;
	std::optional<uint32_t> targetBitrate;
	std::optional<uint32_t> targetFps;
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
