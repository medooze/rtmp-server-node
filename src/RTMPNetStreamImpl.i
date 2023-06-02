%{

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
		double transId = cmd->GetTransId();
		
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
			argv[i++] = Nan::New<v8::Number>(transId);
			for (auto& extra : extras)
			{
				argv[i++] = toJson(extra);
				delete(extra);
			}
			//Call object method with arguments
			MakeCallback(cloned, "oncmd", i, argv);
		});
	}
	
	void SendStatus(double transId, v8::Local<v8::Object> code,v8::Local<v8::Object> level,v8::Local<v8::Object> desc)
	{

		UTF8Parser parserCode;
		UTF8Parser parserLevel;
		UTF8Parser parserDesc;
		parserCode.SetString(*Nan::Utf8String(code));
		parserLevel.SetString(*Nan::Utf8String(level));
		parserDesc.SetString(*Nan::Utf8String(desc));
		fireOnNetStreamStatus(transId, {parserCode.GetWChar(),parserLevel.GetWChar()},parserDesc.GetWChar());
		
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
%}

%nodefaultctor RTMPNetStream;
%nodefaultdtor RTMPNetStream;
class RTMPNetStream
{};
SHARED_PTR(RTMPNetStream)


%nodefaultctor RTMPNetStreamImpl;
class RTMPNetStreamImpl
{
public:
	void SetListener(v8::Local<v8::Object> object);
	void ResetListener();
	void SendStatus(double transId, v8::Local<v8::Object> code,v8::Local<v8::Object> level,v8::Local<v8::Object> desc);
	void AddMediaListener(RTMPMediaStreamListener* listener);
	void RemoveMediaListener(RTMPMediaStreamListener* listener);
	void Stop();
};



SHARED_PTR_BEGIN(RTMPNetStreamImpl)
{
	SHARED_PTR_TO(RTMPNetStream)
}
SHARED_PTR_END(RTMPNetStreamImpl)
