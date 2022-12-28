%{
class RTMPServerModule
{
public:
	typedef std::list<v8::Local<v8::Value>> Arguments;
public:

	~RTMPServerModule()
	{
		Terminate();
	}
	
	/*
	 * Async
	 *  Enqueus a function to the async queue and signals main thread to execute it
	 */
	static void Async(std::function<void()> func) 
	{
		//Check if not terminatd
		if (uv_is_active((uv_handle_t *)&async))
		{
			//Enqueue
			queue.enqueue(std::move(func));
			//Signal main thread
			uv_async_send(&async);
		}
	}

	static void Initialize()
	{
		Log("-RTMPServerModule::Initialize\n");
		//Init async handler
		uv_async_init(uv_default_loop(), &async, async_cb_handler);
	}
	
	static void Terminate()
	{
		Log("-RTMPServerModule::Terminate\n");
		//Close handle
		uv_close((uv_handle_t *)&async, NULL);
		
		std::function<void()> func;
		//Dequeue all pending functions
		while(queue.try_dequeue(func)){}
	}
	
	static void EnableLog(bool flag)
	{
		//Enable log
		Logger::EnableLog(flag);
	}
	
	static void EnableDebug(bool flag)
	{
		//Enable debug
		Logger::EnableDebug(flag);
	}
	
	static void EnableUltraDebug(bool flag)
	{
		//Enable debug
		Logger::EnableUltraDebug(flag);
	}
	
	static void async_cb_handler(uv_async_t *handle)
	{
		std::function<void()> func;
		//Get all pending functions
		while(queue.try_dequeue(func))
		{
			//Execute async function
			func();
		}
	}
	
	
private:
	//http://stackoverflow.com/questions/31207454/v8-multithreaded-function
	static uv_async_t  async;
	static moodycamel::ConcurrentQueue<std::function<void()>> queue;
};


//Static initializaion
uv_async_t RTMPServerModule::async;
moodycamel::ConcurrentQueue<std::function<void()>>  RTMPServerModule::queue;
%}
class RTMPServerModule
{
public:
	static void Initialize();
	static void Terminate();
	static void EnableLog(bool flag);
	static void EnableDebug(bool flag);
	static void EnableUltraDebug(bool flag);
};
