%{

#include "rtmp/rtmpclientconnection.h"

class RTMPClientConnectionImpl :
	public RTMPClientConnection,
	public RTMPClientConnection::Listener
{
public:	
	RTMPClientConnectionImpl(v8::Local<v8::Object> object) :
		RTMPClientConnection(L"")
	{
		//Store event callback object
		persistent = std::make_shared<Persistent<v8::Object>>(object);
	}
	
	RTMPClientConnection::ErrorCode Connect(const char* server,int port, const char* app)
	{
		return RTMPClientConnection::Connect(server, port, app, this);
	}

	void CreateStream(v8::Local<v8::Object> promise)
	{
		SendCommand(0, L"createStream", nullptr, nullptr, promise);
	}

	void DeleteStream(DWORD streamId, v8::Local<v8::Object> promise)
	{
		SendCommand(streamId,L"deleteStream",nullptr,nullptr, promise);
	}

	void Publish(DWORD id, v8::Local<v8::Object> url)
	{
		UTF8Parser parser;
		parser.SetString(*Nan::Utf8String(url));
		RTMPClientConnection::SendCommand(id, L"publish", nullptr, new AMFString(parser.GetWChar()));
	}


	void onConnected(RTMPClientConnection* conn) override
	{
		Log("-RTMPClientConnectionImpl::onConnected()\n");

		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//Call object method with arguments
			MakeCallback(cloned, "onconnected");
		});
	}

	void onDisconnected(RTMPClientConnection* conn, ErrorCode code) override
	{
		Log("-RTMPClientConnectionImpl::onDisconnected()\n");

		//Run function on main node thread
		RTMPServerModule::Async([=,cloned=persistent](){
			Nan::HandleScope scope;
			//Call object method with arguments
			v8::Local<v8::Value> argv[1];
			argv[0] = Nan::New<v8::Int32>(static_cast<int32_t>(code));
			
			MakeCallback(cloned, "ondisconnected", 1, argv);
		});
	}

	void onCommand(RTMPClientConnection* conn, DWORD streamId, const wchar_t* name, AMFData* params, const std::vector<AMFData*>& extra) override
	{
		Log("-RTMPClientConnectionImpl::onCommand()\n");

		std::vector<std::shared_ptr<AMFData>> result;
		result.emplace_back(params->Clone());
		for (auto& e : extra)
			result.emplace_back(e->Clone());

		UTF8Parser parser(name);

		//Run function on main node thread
		RTMPServerModule::Async([=, name = parser.GetUTF8String(), cloned=persistent](){
			Nan::HandleScope scope;
			int i = 0;
			v8::Local<v8::Value> argv[3] = { 
				Nan::New<v8::Number>(streamId),
				Nan::New<v8::String>(name.c_str()).ToLocalChecked(),
				Nan::New<v8::Array>(result.size())
			};
			for (auto& r : result)
				Nan::Set(Nan::To<v8::Object>(argv[2]).ToLocalChecked(), Nan::New<v8::Uint32>(i++), toJson(r.get()));
			//Call object method with arguments
			MakeCallback(cloned, "oncmd", 3, argv);
		});
	}

	void Stop()
	{
		Disconnect();
	}
private:
	void SendCommand(DWORD streamId, const wchar_t* name, AMFData* params, AMFData* extra, v8::Local<v8::Object> promise)
	{
		RTMPClientConnection::SendCommand(streamId, name, params, extra, [=, persistent=std::make_shared<Persistent<v8::Object>>(promise) ](bool isError,AMFData* params, const std::vector<AMFData*>& extra){

			std::vector<std::shared_ptr<AMFData>> result;
			result.emplace_back(params->Clone());
			for (auto& e : extra)
				result.emplace_back(e->Clone());

			RTMPServerModule::Async([=,cloned=persistent](){

				Nan::HandleScope scope;
				int i = 0;
				v8::Local<v8::Value> argv[1] = { Nan::New<v8::Array>(result.size()) };
				for (auto& r : result)
					Nan::Set(Nan::To<v8::Object>(argv[0]).ToLocalChecked(), Nan::New<v8::Uint32>(i++), toJson(r.get()));

				if (isError)
				{
					//Call object method with arguments
					MakeCallback(cloned, "reject", 1, argv);
				} else {
					//Call object method with arguments
					MakeCallback(cloned, "resolve", 1, argv);
				}
			});
		});
	}
private:
	std::shared_ptr<Persistent<v8::Object>> persistent;	
};

%}

%nodefaultctor RTMPClientConnection;
class RTMPClientConnection
{
public:
	enum class ErrorCode
	{
		NoError = 0,
		Generic = 1,
		FailedToResolveURL = 2,
		GetSockOptError = 3,
		FailedToConnectSocket = 4,
		ConnectCommandFailed = 5,
		FailedToParseData = 6,
		PeerClosed = 7,
		ReadError = 8,
		PollError = 9
	};
};


%nodefaultctor RTMPClientConnectionImpl;
class RTMPClientConnectionImpl :
	public RTMPMediaStreamListener
{
public:
	RTMPClientConnectionImpl(v8::Local<v8::Object> object);
	RTMPClientConnection::ErrorCode Connect(const char* server,int port, const char* app);
	void CreateStream(v8::Local<v8::Object> object);
	void Publish(DWORD streamId,v8::Local<v8::Object> url);
	void DeleteStream(DWORD streamId, v8::Local<v8::Object> object);
	QWORD GetInBytes() const;
	QWORD GetOutBytes() const;
	void Stop();
};
