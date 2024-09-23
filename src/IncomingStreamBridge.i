%{
#include "MediaFrameListenerBridge.h"

class IncomingStreamBridge : 
	public RTMPMediaStream::Listener,
	public RTPReceiver
{
private:
	static constexpr size_t BaseVideoSSRC = 2;
public:
	IncomingStreamBridge(v8::Local<v8::Object> object, int maxLateOffset = 200, int maxBufferingTime = 400) :
		audio(new MediaFrameListenerBridge(loop, 1, false, true)),
		videos({
			{0, std::make_shared<MediaFrameListenerBridge>(loop, BaseVideoSSRC, false, true)}
		}),
		mutex(true),
		maxLateOffset(maxLateOffset),
		maxBufferingTime(maxBufferingTime)
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
				if (!hurryUp && ts > now)
				{
					//Log("-IncomingStreamBridge::Dispatch() ReDispatching in %llums size=%d\n",(ts-now).count());
					//Schedule timer for later
					dispatch->Again(ts-now);
					//Done
					break;
				}
				//Log("-IncomingStreamBridge::Dispatch() Dispatched from %llums timestamp:%llu size=%d\n",it->first, frame->GetTimestamp(), queue.size());
				//Check type
				if (frame->GetType()==MediaFrame::Audio)
					//Dispatch audio
					audio->onMediaFrame(*frame);
				else
					//Dispatch video to correct dispatcher
					videos.at(frame->GetSSRC())->onMediaFrame(*frame);
			}
			//No hurry
			hurryUp = false;
		});
		
	}
		
	virtual ~IncomingStreamBridge()
	{
		Log("IncomingStreamBridge::~IncomingStreamBridge()\n");
		Stop();
	}
	
	//Interface
	virtual void onAttached(RTMPMediaStream *stream)
	{
		//Log("-IncomingStreamBridge::onAttached() [streamId:%d]\n",stream->GetStreamId());
		
		ScopedLock scope(mutex);
		
		//Reset audio and video streasm
		audio->Reset();
		for (auto& [id,video] : videos)
			video->Reset();
		
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

		//Stop audio and video
		audio->Stop();
		for (auto& [id,video] : videos)
			video->Stop();

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
	}
	
	void Enqueue(MediaFrame* frame)
	{
		//Get current time
		uint64_t now = getTimeMS();
		
		//Set current time
		frame->SetTime(now);
		
		//Run on thread
		loop.Async([=](...) {
			//Check if it is the first time we see the video track
			if (frame->GetType() == MediaFrame::Video && videos.find(frame->GetSSRC())==videos.end())
			{
				//Get outbound ssrc
				DWORD id   = frame->GetSSRC();
				DWORD ssrc = BaseVideoSSRC + frame->GetSSRC();
				//Log
				Error("-IncomingStreamBridge::Enqueue() | New multivideotrack received [id:%d,ssrc:%d]\n", id, ssrc);
				//Add it
				videos[id] = std::make_shared<MediaFrameListenerBridge>(loop, ssrc, false, true);

				//Fire event on main node thread
				RTMPServerModule::Async([=,cloned=persistent](){
					Nan::HandleScope scope;
					int i = 0;
					v8::Local<v8::Value> argv[1];
					//Create local args
					argv[i++] = Nan::New<v8::Number>(id);
					//Call object method with arguments
					MakeCallback(cloned, "onmultivideotrack", i, argv);
				});
			}

			//Convert timestamp 
			uint64_t timestamp = frame->GetTimeStamp()*1000/frame->GetClockRate();

			//IF it is first
			if (first==std::numeric_limits<uint64_t>::max())
			{
				//Get timestamp
				first = timestamp;
				//Get current time
				ini = now;

				Debug("-IncomingStreamBridge::Enqueue() First frame %s scheduled timestamp:%lu ini:%llu queue:%d\n", 
					frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
					frame->GetTimeStamp(),
					ini,
					queue.size()
				);
			}

			//Check when it has to be sent
			auto sched = ini + (timestamp - first);

			//Is this frame too late? (allow 200ms offset)
			if (sched < now && sched + maxLateOffset > now)
			{
				UltraDebug("-IncomingStreamBridge::Enqueue() Got late frame %s timestamp:%lu(%llu) time:%llu(%llu) ini:%llu sched:%llu now:%llu first:%llu queue:%d\n",
					frame->GetType() == MediaFrame::Video ? "VIDEO" : "AUDIO",
					frame->GetTimeStamp(),
					timestamp,
					frame->GetTime() - ini,
					frame->GetTime(),
					ini,
					sched,
					now,
					first,
					queue.size()
				);
				//If there are no other on the queue
				if (queue.empty())
				{
					//Update timestamp for first
					first = timestamp;
					//Get current time
					ini = now;
					//Send now
					sched = now;

					Debug("-IncomingStreamBridge::Enqueue() Reseting first frame %s scheduled timestamp:%lu ini:%llu queue:%d\n", 
						frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
						frame->GetTimeStamp(),
						ini,
						queue.size()
					);
				} else {
					//Use last frame time
					sched = queue.back().first;
				}
			//Do not queue more than 200ms
			} else if (sched > now + maxBufferingTime) {
                                Debug("-IncomingStreamBridge::Enqueue() Hurry Up!\n");
				//release all frames now
                                hurryUp = true;
				 //Update timestamp for first
                                first = timestamp;
                                //Get current time
                                ini = now;
                                //Send now
                                sched = now;
                        }


			/*Log("-IncomingStreamBridge::Enqueue() Frame %s scheduled in %lldms timestamp:%lu time:%llu rel:%llu first:%lu ini:%llu queue:%d\n", 
				frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
				sched - now,
				frame->GetTimeStamp(),
				frame->GetTime()-ini,
				frame->GetTime()-first,
				first,
				ini,
				queue.size()
			);*/
			//Enqueue
			queue.emplace_back(sched,frame);

			//If we need to drain the queue			
			if (hurryUp) 
			{
				//Run now
                                dispatch->Again(0ms);
                        } 
			//If queue was empty
			else if (queue.size()==1)
			{
				//Log("-IncomingStreamBridge::Enqueue() Dispatching in %llums size=%u\n",sched > now ? sched - now : 0, queue.size());
				//Schedule timer for later
				dispatch->Again(std::chrono::milliseconds(sched > now ? sched - now : 0));
			}
		});
	}
	
	virtual void onMediaFrame(DWORD id,RTMPMediaFrame *frame)
	{
		//Update sender time if we have timing ingo
		if (timingInfo.first && timingInfo.second <= frame->GetTimestamp())
			//Calculate sender time from timestamp diff
			frame->SetSenderTime(timingInfo.first + frame->GetTimestamp() - timingInfo.second);

		//Depending on the type
		switch (frame->GetType())
		{
			case RTMPMediaFrame::Video:
			{
				//Get frame
				auto rtmpVideoFrame = static_cast<RTMPVideoFrame*>(frame);
				//Get track id
				auto trackId = rtmpVideoFrame->GetTrackId();
				//Get video codec from rtmp codec
				auto codec = GetRtmpFrameVideoCodec(*rtmpVideoFrame);
				//Get or create ptr for depaketizer
				auto& videoPacketizer = videoPacketizers[trackId];
				//Check if we have one already for same codec
				if (!videoPacketizer || videoPacketizer->GetCodec()!=codec)
				{
					Debug("-IncomingStreamBridge::onMediaFrame() | Creating new video packetizer [trackId:%d,codec:%d]\n",trackId,codec);
					//Create a new one
					videoPacketizer = std::move(CreateRTMPVideoPacketizer(codec));
					//Check codec is valid
					if (!videoPacketizer)
						// Not supported yet
						return (void)Warning("-IncomingStreamBridge::onMediaFrame() | Video codec not supported, dropping frame codec:%d\n", codec);
				}

				//Create rtp packets
				std::unique_ptr<VideoFrame> videoFrame = videoPacketizer->AddFrame(rtmpVideoFrame);

				//IF got one
				if (videoFrame)
				{
					//Set trackId
					videoFrame->SetSSRC(trackId);

					//Set target bitrate if got it from metadata event
					if (auto it = videodatarates.find(trackId); it != videodatarates.end())
						videoFrame->SetTargetBitrate((uint32_t)it->second);
					//Set frame rate too
					if (auto it = framerates.find(trackId); it != framerates.end())
						videoFrame->SetTargetFps((uint32_t)it->second);
					//Push it
					Enqueue(videoFrame.release());
				} 
				break;
			}
			case RTMPMediaFrame::Audio:
			{
				//Get frame
				auto rtmpAudioFrame = static_cast<RTMPAudioFrame*>(frame);
				auto codec = GetRtmpFrameAudioCodec(*rtmpAudioFrame);
				//Check if we have one already for same codec
				if (!audioPacketizer || audioPacketizer->GetCodec()!=codec)
				{
					Log("-IncomingStreamBridge::onMediaFrame() | Creating new audio packetizer [codec:%d]\n",codec);
					//Create a new one
					audioPacketizer = std::move(CreateRTMPAudioPacketizer(codec));
					//Check codec is valid
					if (!audioPacketizer)
						// Not supported yet
						return (void)Warning("-IncomingStreamBridge::onMediaFrame() | Audio codec not supported, dropping frame codec:%d\n", codec);
				}
				//Create rtp packet
				std::unique_ptr<AudioFrame> audioFrame = audioPacketizer->AddFrame(rtmpAudioFrame);
				//IF got one
				if (audioFrame)
					//Push it
					Enqueue(audioFrame.release());

				//TODO: deprecate
				if (codec == AudioCodec::AAC)
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
				break;
			}
		}
	}

	virtual void onMetaData(DWORD id,RTMPMetaData *meta) 
	{
		if (meta->GetParamsLength()<1)
		{
			Warning("-IncomingStreamBridge::onMetaData() Not enough params to get name"); 
			return;
		}
		
		//Get command name
		std::wstring name = *meta->GetParams(0);

		Debug("-IncomingStreamBridge::onMetaData() [streamId:%d,name:%ls]\n", id, name.c_str());

		try {
			if (name.compare(L"onFi")==0 || name.compare(L"onFI")==0)
			{
				if (meta->GetParamsLength()<2)
					return;

				//Get medatada params
				AMFData* params = meta->GetParams(1);

				//Check the different variants
				if (params->CheckType(AMFData::EcmaArray))
				{
				
					//Get timecode info
					AMFEcmaArray* timecode = (AMFEcmaArray*)params;

					//Ensure it has sd and st fields
					if (!timecode->HasProperty(L"sd") || !timecode->HasProperty(L"st"))
					{
						Warning("-IncomingStreamBridge::onMetaData() onFi does not contain sd and st params\n"); 
						return;
					}

					//Get the date
					uint32_t year = 0;
					uint32_t month = 0;
					uint32_t day = 0;
					uint32_t hour = 0;
					uint32_t minute = 0;
					uint32_t second = 0;
					uint32_t millisecond = 0;

					std::wstring sd = timecode->GetProperty(L"sd");
					std::wstring st = timecode->GetProperty(L"st");

					swscanf(sd.c_str(), L"%02u-%02u-%04u", &day, &month, &year);
					swscanf(st.c_str(), L"%02u:%02u:%02u.%03u", &hour, &minute, &second, &millisecond);

					struct tm timeinfo = {};

					timeinfo.tm_year = year - 1900; // Year - 1900
					timeinfo.tm_mon = month - 1;	// Month, where 0 = jan
					timeinfo.tm_mday = day;         // Day of the month
					timeinfo.tm_hour = hour;
					timeinfo.tm_min = minute;
					timeinfo.tm_sec = second;
					timeinfo.tm_isdst = -1;         // Is DST on? 1 = yes, 0 = no, -1 = unknown

					//Set timing info
					timingInfo.first  = mktime(&timeinfo) * 1000 + millisecond;
					timingInfo.second = meta->GetTimestamp();

				} else if (params->CheckType(AMFData::Object)) {
				
					//If we don't have the video fps from the metadata event
					if (framerates.find(0)==framerates.end() || !framerates[0])
						return;

					//Get timecode info
                                        AMFObject* timecode = (AMFObject*)params;

                                        //Check we have the timecode
                                        if (!timecode->HasProperty(L"tc"))
                                        {
                                                Warning("-IncomingStreamBridge::onMetaData() onFi does not contain tc params\n");
                                                return;
                                        }

                                        //Get the timestamp
                                        uint32_t hour = 0;
                                        uint32_t minute = 0;
                                        uint32_t second = 0;
                                        uint32_t frames = 0;

                                        std::wstring tc = timecode->GetProperty(L"tc");

                                        swscanf(tc.c_str(), L"%02u:%02u:%02u:%02u", &hour, &minute, &second, &frames);

                                        time_t rawtime;
                                        time (&rawtime);
                                        tm* timeinfo = localtime (&rawtime);

                                        timeinfo->tm_hour = hour;
                                        timeinfo->tm_min = minute;
                                        timeinfo->tm_sec = second;
                                        timeinfo->tm_isdst = -1;         // Is DST on? 1 = yes, 0 = no, -1 = unknown

                                        //Set timing info
                                        timingInfo.first  = mktime(timeinfo) * 1000 + 1000 * frames / framerates[0];
                                        timingInfo.second = meta->GetTimestamp();
				}
			} else if (name.compare(L"@setDataFrame")==0) {
				if (meta->GetParamsLength()<3)
				{
					Warning("-IncomingStreamBridge::onMetaData() Not enough params on @setDataFrame\n"); 
					return;
				}
				
				//Get medatada params
				std::wstring metadata = *(meta->GetParams(1));
				AMFData* params = meta->GetParams(2);
				

				//Check metadata name and propper data type
				if (metadata.compare(L"onMetaData")!=0)
				{
					Warning("-IncomingStreamBridge::onMetaData() Unknown @setDataFrame name\n"); 
					return;
				}
				
				if (params->CheckType(AMFData::EcmaArray) || params->CheckType(AMFData::Object))
				{

					//Get data
					AMFNamedPropertiesObject* data = (AMFNamedPropertiesObject*)params;

					//Get video fps if present
					if (data->HasProperty(L"videodatarate"))
						videodatarates[0] = (double)data->GetProperty(L"videodatarate");
					if (data->HasProperty(L"framerate"))
						framerates[0] = (double)data->GetProperty(L"framerate");

					//Get the multivideo track info map
					if (data->HasProperty(L"videoTrackIdInfoMap"))
					{
						AMFData* map = &data->GetProperty(L"videoTrackIdInfoMap");

						if (map->CheckType(AMFData::EcmaArray) || map->CheckType(AMFData::Object))
						{
							//Get data
							AMFNamedPropertiesObject* videoTrackIdInfoMap = (AMFNamedPropertiesObject*)map;

							//For each trak
							for (const auto& [key, val] : videoTrackIdInfoMap->GetProperties())
							{
								if (val->CheckType(AMFData::EcmaArray) || val->CheckType(AMFData::Object))
								{
									//Get trackId
									int trackId = std::stoi(key);
									//Get data
									AMFNamedPropertiesObject* datatrack = (AMFNamedPropertiesObject*)val;
									//Get video fps if present
									if (datatrack->HasProperty(L"videodatarate"))
										videodatarates[trackId] = (double)datatrack->GetProperty(L"videodatarate");
									if (datatrack->HasProperty(L"framerate"))
										framerates[trackId] = (double)datatrack->GetProperty(L"framerate");
								}
							}
						}
					}

				} else {
					Warning("-IncomingStreamBridge::onMetaData() Unknown @setDataFrame metatada\n"); 
					return;
				}

				

			} else if (name.compare(L"onTextData")==0) {
				if (meta->GetParamsLength()<2)
					return;

				//Get medatada params
				AMFData* params = meta->GetParams(1);

				//Check the different variants
				if (params->CheckType(AMFData::EcmaArray))
				{

					//Get timecode info
					AMFObject* timecode = (AMFObject*)params;

					//Check we have the timecode
					if (!timecode->HasProperty(L"ts"))
					{
						Warning("-IncomingStreamBridge::onMetaData() onTextData does not contain ts param\n");
						return;
					}

					//Get the timestamp
					std::wstring ts = timecode->GetProperty(L"ts");

                                        wchar_t* end;
					unsigned long time = std::wcstoul(ts.c_str(), &end, 10);

					//Set timing info
					timingInfo.first  = time;
					timingInfo.second = meta->GetTimestamp();
				}
			}
		} catch (...)
		{
			Warning("-IncomingStreamBridge::onMetaData() exception parsing metadata\n"); 
		}

	};
	virtual void onCommand(DWORD id,const wchar_t *name,AMFData* obj)
	{
		Debug("-IncomingStreamBridge::onCommand() [streamId:%d,name:%ls]\n",id,name);
	};
	virtual void onStreamBegin(DWORD id)
	{
		
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

	virtual int Reset(DWORD ssrc)
	{
		//oh, not possible on rtmp
		return 1;
	}
	
	MediaFrameListenerBridge::shared& GetAudio()	{ return audio;		}
	MediaFrameListenerBridge::shared& GetVideo()	{ return videos[0];	}

	MediaFrameListenerBridge::shared& GetMultitrackVideo(DWORD id)	
	{
		return videos.at(id);	
	}
	
private:
	EventLoop loop;

	std::unique_ptr<RTMPAudioPacketizer> audioPacketizer;
	std::map<uint8_t,std::unique_ptr<RTMPVideoPacketizer>> videoPacketizers;

	MediaFrameListenerBridge::shared audio;
	std::map<uint8_t,MediaFrameListenerBridge::shared> videos;

	Mutex mutex;
	RTMPMediaStream *attached = nullptr;
	std::shared_ptr<Persistent<v8::Object>> persistent;	
	std::vector<std::pair<uint64_t,std::unique_ptr<MediaFrame>>> queue;
	Timer::shared dispatch;
		
	uint64_t first = std::numeric_limits<uint64_t>::max();
	uint64_t ini = std::numeric_limits<uint64_t>::max();
	bool stopped = false;
	bool hurryUp = false;
	int maxLateOffset = 200;
	int maxBufferingTime = 400;
	std::pair<uint64_t,uint64_t> timingInfo = {};
	std::map<size_t, double> videodatarates;
	std::map<size_t, double> framerates;
	
};

%}


class IncomingStreamBridge : public RTMPMediaStreamListener
{
public:
	IncomingStreamBridge(v8::Local<v8::Object> object, int maxLateOffset = 200, int maxBufferingTime = 400);
	MediaFrameListenerBridgeShared GetAudio();
	MediaFrameListenerBridgeShared GetVideo();
	MediaFrameListenerBridgeShared GetMultitrackVideo(DWORD id);
	void Stop();
};