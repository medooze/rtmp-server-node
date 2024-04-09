%include "RTMPNetStreamImpl.i"

%{

class RTMPNetConnectionImpl :
	public RTMPNetConnection
{
public:	
	RTMPNetConnectionImpl(Listener *listener,std::function<void(bool)> accept) :
		accept(accept)
	{
		//Add us as listeners
		AddListener(listener);
	}

	void Accept(v8::Local<v8::Object> object)
	{
		//Store event callback object
		persistent = std::make_shared<Persistent<v8::Object>>(object);
		//Accept connection
		accept(true);
	}
	
	void Reject()
	{
		//Reject connection
		accept(false);
	}

	virtual RTMPNetStream::shared CreateStream(DWORD streamId,DWORD audioCaps,DWORD videoCaps,RTMPNetStream::Listener *listener) override
	{
		Log("-RTMPNetConnectionImpl::CreateStream() [streamId:%d]\n",streamId);
		
		//Create stream
		auto stream = std::make_shared<RTMPNetStreamImpl>(streamId,listener);
		
		//Register stream
		RegisterStream(stream);
		
		//Check we have a callback object
		if (!persistent || persistent->IsEmpty())
			//Do nothing
			return stream;
		
		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//We create anothger shared pointer
			auto shared = new std::shared_ptr<RTMPNetStreamImpl>(stream);
			//Create local args
			v8::Local<v8::Value> argv[1] = {
				SWIG_NewPointerObj(SWIG_as_voidptr(shared), SWIGTYPE_p_RTMPNetStreamImplShared,SWIG_POINTER_OWN)
			};
			//Call object method with arguments
			MakeCallback(cloned, "onstream", 1, argv);
		});
		
		return stream;
	}

	virtual void DeleteStream(const RTMPNetStream::shared& stream) override
	{
		Log("-RTMPNetConnectionImpl::DeleteStream() [streamId:%d]\n",stream->GetStreamId());
		
		//Cast
		auto impl = std::static_pointer_cast<RTMPNetStreamImpl>(stream);
		//Signael stop event
		impl->Stop();
		//Unregister stream
		UnRegisterStream(stream);
	}
	
	virtual void Disconnect()
	{
		//Ensure no callback is fired
		persistent.reset();
		//Disconnect
		RTMPNetConnection::Disconnect();
	}
	
	virtual void Disconnected() 
	{
		RTMPNetConnection::Disconnected();
		
		if (!persistent || persistent->IsEmpty())
			//Do nothing
			return;
	
		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//Call object method with arguments
			MakeCallback(cloned, "ondisconnect");
		});
	}
private:
	std::function<void(bool)> accept;
	std::shared_ptr<Persistent<v8::Object>> persistent;	
};

%}

%nodefaultctor RTMPNetConnection;
%nodefaultdtor RTMPNetConnection;
class RTMPNetConnection
{};

SHARED_PTR(RTMPNetConnection)

%nodefaultctor RTMPNetConnectionImpl;
class RTMPNetConnectionImpl :
	public RTMPNetConnection
{
public:
	void Accept(v8::Local<v8::Object> object);
	void Reject();
	void Disconnect();
};

SHARED_PTR_BEGIN(RTMPNetConnectionImpl)
{
	SHARED_PTR_TO(RTMPNetConnection)
}
SHARED_PTR_END(RTMPNetConnectionImpl)