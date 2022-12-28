%{
class RTMPServerFacade : 
	public RTMPServer
{
public:	
	RTMPServerFacade(v8::Local<v8::Object> object)
	{
		persistent = std::make_shared<Persistent<v8::Object>>(object);
	}
	void Start(int port)
	{
		Init(port);
	}

	void AddApplication(v8::Local<v8::Object> name,RTMPApplicationImpl *app)
	{
		UTF8Parser parser;
		parser.SetString(*Nan::Utf8String(name));
		RTMPServer::AddApplication(parser.GetWChar(),app);
	}
	
	void Stop()
	{
		End();
	}
private:
	std::shared_ptr<Persistent<v8::Object>> persistent;	
};

%}

class RTMPServerFacade
{
public:	
	RTMPServerFacade(v8::Local<v8::Object> object);
	void Start(int port);
	void AddApplication(v8::Local<v8::Object> name,RTMPApplicationImpl *app);
	void Stop();
};
