const tap			= require("tap");
const RTMPServer		= require("../index.js");

RTMPServer.enableLog(true);
RTMPServer.enableDebug(true);
RTMPServer.enableUltraDebug(true);

//Try to clean up on exit
const onExit = (e) =>
{
	if (e) console.error(e);
	process.exit();
};

function sleep(ms)
{
	return new Promise(resolve => setTimeout(resolve, ms));
}

process.on("uncaughtException", onExit);
process.on("SIGINT", onExit);
process.on("SIGTERM", onExit);
process.on("SIGQUIT", onExit);

tap.test("Server", async function (suite)
{

	await suite.test("publish+unpublish", async function (test)
	{
		test.plan(6);

		let incomingStream,outgoingStream;
		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		app.on("connect", (client) =>
		{
			//Add publish listener
			client.on("stream", (stream) =>
			{
				//Send to server
				test.ok(stream, "Got stream on server");
				//Listen for commands
				stream.on("cmd",async(cmd, transId, ...params) => {
					if (cmd.name == "publish")
					{
						//Got publish cmd
						test.ok(stream, "Got publish cmd");
						//Create incoming stream
						incomingStream = stream.createIncomingStreamBridge();
						//Got incoming stream
						test.ok(incomingStream, "Got incoming stream");
						//Started
						stream.sendStatus(transId, RTMPServer.NetStream.Publish.Start);
					}
				})
			});
			//Accept client connection by default
			client.accept();
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1935);

		//Create client connection
		const connection = RTMPServer.createClientConnection();

		connection.on("connected",async ()=>{

			test.pass("client connected");

			outgoingStream = await connection.publish("test");

			test.ok(outgoingStream, "got stream on client");

			outgoingStream.on("cmd", (stream, name, cmd)=>{
				//Got publishing command
				test.same(cmd[1].code, RTMPServer.NetStream.Publish.Start.code)
			});

			
		});

		//Connect
		connection.connect("127.0.0.1", 1935, "test");

		//Wait 1 seconds
		await sleep(1000);

		//Attach streams
		outgoingStream.attachTo(incomingStream);

		connection.on("disconnected",()=>{
			test.pass("client disconnected");
		});

		//Stop
		connection.stop();

		//Wait 1 seconds
		await sleep(1000);

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	await suite.test("failed", async function (test)
	{
		//Create client connection
		const connection = RTMPServer.createClientConnection();

		connection.on("disconnected",()=>{
			test.pass("client disconnected");
		});

		//Connect
		connection.connect("127.0.0.1", 1936, "test");
		
		//Wait 1 seconds
		await sleep(1000);
	});
	suite.end();

}).then(() =>
{
	RTMPServer.terminate();
});

