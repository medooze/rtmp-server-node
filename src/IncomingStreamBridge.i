%{
#include "MediaFrameListenerBridge.h"


class IncomingStreamBridge : 
	public RTMPMediaStream::Listener,
	public RTPReceiver
{
public:
	IncomingStreamBridge(v8::Local<v8::Object> object) :
		audio(new MediaFrameListenerBridge(loop, 1)),
		video(new MediaFrameListenerBridge(loop, 2)),
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
					//Dispatch video
					video->onMediaFrame(*frame);
			}
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
		
		//Run on thread
		loop.Async([=](...) {
			//Ensure that we are not overflowing
			if (queue.size()>2048)
			{
				//Show error
				Error("-IncomingStreamBridge::Enqueue() Queue buffer overflowing, cleaning it [size:%d]\n",queue.size());
				//Clear all pending data
				queue.clear();
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
			if (sched < now && sched + 200 > now)
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
			
			//If queue was empty
			if (queue.size()==1)
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
	bool stopped = false;
};

%}


class IncomingStreamBridge : public RTMPMediaStreamListener
{
public:
	IncomingStreamBridge(v8::Local<v8::Object> object);
	MediaFrameListenerBridgeShared GetAudio();
	MediaFrameListenerBridgeShared GetVideo();
	void Stop();
};