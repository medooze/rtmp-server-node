%{
#include "MediaFrameListenerBridge.h"


class IncomingStreamBridge : 
	public RTMPMediaStream::Listener,
	public RTPReceiver
{
public:
	IncomingStreamBridge(v8::Local<v8::Object> object, int maxLateOffset = 200, int maxBufferingTime = 400) :
		audio(new MediaFrameListenerBridge(loop, 1)),
		video(new MediaFrameListenerBridge(loop, 2)),
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

				int64_t diff = lastConsumed;
				lastConsumed = frame->GetTimeStamp()*1000/frame->GetClockRate();
				diff = lastConsumed - diff;

				uint64_t n = getTimeMS();
				//Log("-IncomingStreamBridge::Dispatch() Dispatched from %llums delayed: %llu timestamp:%llu adjusted: %llu diff:%lld qsize=%d type:%s\n",
				//	it->first, 
				//	n - frame->GetTime(), 
				//	frame->GetTimestamp(), 
				//	lastConsumed, 
				//	diff, 
				//	queue.size(), 
				//	(frame->GetType() == MediaFrame::Audio ? "AUDIO" : "VIDEO"));
				
				//Check type
				if (frame->GetType()==MediaFrame::Audio)
					//Dispatch audio
					audio->onMediaFrame(*frame);
				else
					//Dispatch video
					video->onMediaFrame(*frame);
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
		
		void* bridge = this;
		//Run on thread
		loop.Async([=](...) {
			//Convert timestamp 
			uint64_t timestamp = frame->GetTimeStamp()*1000/frame->GetClockRate();
			
			// @todo This JB implementation wwont cope with random TS resetting on remote end and otehr abnormalities but will make a consistent flow/latency adjustment for this test

			// If it is first OR we got the first timestamp out of order and chose a later one to sync on
			// I.e. We want to sync on the earliest timestamp to make life easier
			if (timestamp < first)
			{
				//Get timestamp
				first = timestamp;
				//Get current time
				ini = now;
				lastConsumed = first;
				iniAdj = 0;
				maxJitter = 0;

				Debug("-IncomingStreamBridge::Enqueue() First frame %s scheduled timestamp:%lu ini:%llu queue:%d\n", 
					frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
					frame->GetTimeStamp(),
					ini,
					queue.size()
				);
			}

			// @todo Note: We are NOT shrinking this jitter buffer, only expanding it for the moment

			assert(timestamp >= first);
			auto diff = timestamp - first;

			// Time should only go forwards
			assert(now >= ini);
			auto tdiff = now - (ini + iniAdj);

			// Calc if this packet arrived earlier than the anchor expectation
			if (tdiff < diff)
			{
				// Early packet according to current anchor. 
				// Need to resync anchor to always point to the earliest packet so time diffs are always positive to make life easier
				auto anchorEarlier = diff - tdiff;

				Debug("-IncomingStreamBridge::Enqueue() Early frame changing anchor (increases jb size) %s adjusted:%llu ini:%llu iniAdj:%lld first:%llu adjusting by: %lld\n", 
					frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
					timestamp,
					ini,
					iniAdj,
					first,
					anchorEarlier
				);

				iniAdj -= anchorEarlier;
				tdiff = diff;

				// @todo In theory increases maxJitter by anchorEarlier as well but wont do that allow it to increase naturally
			}
			//else
			//{
			//	// On time or late
			//}
			auto jitter = tdiff - diff;

			if (jitter > maxJitter)
			{
				Debug("-IncomingStreamBridge::Enqueue increase jitter buffer size () %s adjusted:%llu ini:%llu iniAdj:%lld first:%llu jitter: %llu maxjitter:%llu\n", 
					frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
					timestamp,
					ini,
					iniAdj,
					first,
					jitter,
					maxJitter
				);
			}
			maxJitter = std::max(maxJitter, jitter);

			// Check when it has to be sent (always ideal time + jitter)
			auto sched = ini + iniAdj + diff + maxJitter;

			/*
			//Is this frame too late? (allow 200ms offset)
			if (sched < now && sched + maxLateOffset > now)
			{
				Debug("-IncomingStreamBridge::Enqueue() Got late frame %s timestamp:%lu(%llu) time:%llu(%llu) ini:%llu sched:%llu now:%llu first:%llu queue:%d\n",
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
					lastConsumed = first;

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
								lastConsumed = first;
                        }
			*/

			// Find where on queue to put it
			// Note: We want to order based on timestamp, NOT scheduled
			// In theory scheduled is in order but not when we do adjustements to it etc
			auto insertIt = queue.begin();
			size_t insertIndex = 0;
			for (; insertIt != queue.end(); ++insertIt, ++insertIndex)
			{
				uint64_t ts = insertIt->second->GetTimeStamp()*1000/ insertIt->second->GetClockRate();
				if (ts > timestamp)
				{
					break;
				}
			}

			// @todo wont cope with weirdness in timestamps but sufficient for our test
			if (timestamp < lastConsumed)
			{
				Log("-IncomingStreamBridge::Enqueue later than JB size cant be consumed dropping() %p F:%p Frame %s arrived too late DROPPING as already consumed past its timestamp would be scheduled in %lldms timestamp:%lu adjusted:%llu time:%llu rel:%llu first:%lu ini:%llu queue:%d lastConsumed:%llu maxJitter:%llu, insertIndex:%u\n", 
					bridge,
					(void*)frame,
					frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
					sched - now,
					frame->GetTimeStamp(),
					timestamp,
					frame->GetTime()-ini,
					frame->GetTime()-first,
					first,
					ini,
					queue.size(),
					lastConsumed,
					maxJitter,
					(unsigned int)insertIndex
				);

				// @todo Are we leaking this frame?
				return;
			}

			/*
			Log("-IncomingStreamBridge::Enqueue() %p F:%p Frame %s scheduled in %lldms timestamp:%lu adjusted:%llu time:%llu rel:%llu first:%lu ini:%llu queue:%d lastConsumed:%llu maxJitter:%llu\n", 
				bridge,
				(void*)frame,
				frame->GetType()== MediaFrame::Video ? "VIDEO": "AUDIO",
				sched - now,
				frame->GetTimeStamp(),
				timestamp,
				frame->GetTime()-ini,
				frame->GetTime()-first,
				first,
				ini,
				queue.size(),
				lastConsumed,
				maxJitter
			);
			*/
			queue.emplace(insertIt, sched,frame);

			//If we need to drain the queue			
			if (hurryUp) 
			{
				//Run now
				dispatch->Again(0ms);
			} 
			//If queue was empty
			else if (insertIndex == 0)
			{
				//Log("-IncomingStreamBridge::Enqueue() Dispatching in %llums size=%u\n",sched > now ? sched - now : 0, queue.size());
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
				std::unique_ptr<VideoFrame> videoFrame;
				
				auto vframe = static_cast<RTMPVideoFrame*>(frame);
				auto codec = GetRtmpFrameVideoCodec(*vframe);

				switch(codec)
				{
					case VideoCodec::H265:
						videoFrame = hevcPacketizer.AddFrame(vframe);
						break;
					case VideoCodec::H264:
					 	videoFrame= avcPacketizer.AddFrame(vframe);
						break;
					case VideoCodec::AV1:
						videoFrame= av1Packetizer.AddFrame(vframe);
						break;
					default:
						// Not supported yet
						Warning("-IncomingStreamBridge::onMediaFrame() | Video codec not supported, dropping frame codec:%d\n", codec);
						return;
				}
				
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

	virtual int Reset(DWORD ssrc)
	{
		//oh, not possible on rtmp
		return 1;
	}
	
	MediaFrameListenerBridge::shared& GetAudio()	{ return audio; }
	MediaFrameListenerBridge::shared& GetVideo()	{ return video; }
	
private:
	EventLoop loop;
	RTMPAVCPacketizer avcPacketizer;
	RTMPHEVCPacketizer hevcPacketizer;
	
	RTMPAv1Packetizer av1Packetizer;
	
	RTMPAACPacketizer aacPacketizer;
	MediaFrameListenerBridge::shared audio;
	MediaFrameListenerBridge::shared video;
	Mutex mutex;
	RTMPMediaStream *attached = nullptr;
	std::shared_ptr<Persistent<v8::Object>> persistent;	
	std::vector<std::pair<uint64_t,std::unique_ptr<MediaFrame>>> queue;
	Timer::shared dispatch;
		
	uint64_t first = std::numeric_limits<uint64_t>::max();
	uint64_t ini = std::numeric_limits<uint64_t>::max();
	int64_t iniAdj = 0;
	uint64_t maxJitter = 0;
	uint64_t lastConsumed = std::numeric_limits<uint64_t>::max();
	bool stopped = false;
	bool hurryUp = false;
	int maxLateOffset = 200;
	int maxBufferingTime = 400;
};

%}


class IncomingStreamBridge : public RTMPMediaStreamListener
{
public:
	IncomingStreamBridge(v8::Local<v8::Object> object, int maxLateOffset = 200, int maxBufferingTime = 400);
	MediaFrameListenerBridgeShared GetAudio();
	MediaFrameListenerBridgeShared GetVideo();
	void Stop();
};
