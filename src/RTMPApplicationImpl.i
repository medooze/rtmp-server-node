%include "RTMPNetConnectionImpl.i"

%{
#include <arpa/inet.h>

class RTMPApplicationImpl : 
	public RTMPApplication
{
public:
	RTMPApplicationImpl(v8::Local<v8::Object> object)
	{
		persistent = std::make_shared<Persistent<v8::Object>>(object);
	}

	virtual ~RTMPApplicationImpl() = default;

	virtual RTMPNetConnection::shared Connect(const struct sockaddr_in& peername, const std::wstring& appName,RTMPNetConnection::Listener *listener,std::function<void(bool)> accept) override
	{
		//Create connection pointer
		auto connection = std::make_shared<RTMPNetConnectionImpl>(listener,accept);
		
		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//We create shared pointer for connection pointer
			auto shared = new std::shared_ptr<RTMPNetConnectionImpl>(connection);
			//Create local args
			char peeripBuf [32];
			auto peerip = Nan::New<v8::String>(inet_ntop(AF_INET, &peername.sin_addr, peeripBuf, sizeof(peeripBuf)));
			auto peerport = Nan::New<v8::Uint32>(ntohs(peername.sin_port));
			UTF8Parser parser(appName);
			auto str	= Nan::New<v8::String>(parser.GetUTF8String());
			auto object	= SWIG_NewPointerObj(SWIG_as_voidptr(shared), SWIGTYPE_p_RTMPNetConnectionImplShared,SWIG_POINTER_OWN);
			//Create arguments
			v8::Local<v8::Value> argv[4] = {
				peerip.ToLocalChecked(),
				peerport,
				str.ToLocalChecked(),
				object
			};
			
			//Call object method with arguments
			MakeCallback(cloned, "onconnect", 4, argv);
		});
		
		return connection;
	}
private:
	std::shared_ptr<Persistent<v8::Object>> persistent;	
};

%}

class RTMPApplicationImpl
{
public:
	RTMPApplicationImpl(v8::Local<v8::Object> object);
};
