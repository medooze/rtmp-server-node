const tap			= require("tap");
const RTMPServer		= require("../index.js");

RTMPServer.enableWarning(false);
RTMPServer.enableLog(false);
RTMPServer.enableDebug(false);
RTMPServer.enableUltraDebug(false);

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

function promise()
{
	let resolve;
	let reject;
	const promise = new Promise((_resolve, _reject) => {
		resolve = _resolve;
		reject = _reject;
	});
	promise.resolve = resolve;
	promise.reject = reject;
	return promise;
}


process.on("uncaughtException", onExit);
process.on("SIGINT", onExit);
process.on("SIGTERM", onExit);
process.on("SIGQUIT", onExit);

tap.test("Server", async function (suite)
{
	await suite.test("publish+unpublish", async function (test)
	{
		test.plan(8);

		let incomingStream,outgoingStream;
		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();

		const serverConnected = promise();
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
						serverConnected.resolve();
					}
				})
			});
			//Accept client connection by default
			client.accept();
		});

		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1936);

		//Create client connection
		const connection = RTMPServer.createClientConnection();

		const connected = promise();
		connection.on("connected",async ()=>{

			test.pass("client connected");

			outgoingStream = await connection.publish("test");

			test.ok(outgoingStream, "got stream on client");

			outgoingStream.on("cmd", (stream, name, cmd)=>{
				//Got publishing command
				test.same(cmd[1].code, RTMPServer.NetStream.Publish.Start.code, "Client got publishing cmd")
				//Attach streams
				outgoingStream.attachTo(incomingStream);
				connected.resolve();
			});
		});

		connection.on("disconnected",(conn, errorCode)=>{
			test.fail("Expected stopped not disconnected event");
		});

		const stopped = promise();
		connection.on("stopped",(conn)=>{
			test.pass("client connection stopped");
			stopped.resolve();
		});


		//Connect
		connection.connect("127.0.0.1", 1936, "test");
		await connected;
		await serverConnected;

		//Check we have stats
		test.ok(connection.getStats(), "Client connection got stats");

		//Stop
		connection.stop();
		await stopped;

		//Stop server
		rtmp.stop();

		//OK
		test.end();
	});

	await suite.test("incorrectport", async function (test)
	{
		//Create client connection
		const connection = RTMPServer.createClientConnection();

		const disconnected = promise();
		connection.on("disconnected", (conn, errorCode)=>{
			test.equal(errorCode, RTMPServer.NetConnectionErrorCode.PollError);
			disconnected.resolve();
		});

		//Connect. Note the connect wouldn't fail immediately.
		let errorCode = connection.connect("127.0.0.1", 193734, "test");
		test.equal(errorCode, RTMPServer.NetConnectionErrorCode.NoError);
		
		await disconnected;
		
		test.end();
	});
	
	await suite.test("invalidurl", async function (test)
	{
		//Create client connection
		const connection = RTMPServer.createClientConnection();

		//Connect
		let errorCode = connection.connect("invalid.url", 1937, "test");
		test.equal(errorCode, RTMPServer.NetConnectionErrorCode.FailedToResolveURL);
		
		test.end();
	});
	
	await suite.test("peerclosed", async function (test)
	{
		test.plan(3);
		
		//Create server and app
		const app = RTMPServer.createApplication();
		const rtmp = RTMPServer.createServer();
		
		app.on("connect", (client) =>
		{
			// Close the connection
			test.pass("Server rejecting client");
			client.reject();
		});
		
		//Start rtmp server
		rtmp.addApplication("test", app);
		rtmp.start(1936);
				
		//Create client connection
		const connection = RTMPServer.createClientConnection();

		const disconnected = promise();
		connection.on("disconnected", (conn, errorCode)=>{
			test.equal(errorCode, RTMPServer.NetConnectionErrorCode.PeerClosed, "Client expects peer closed when server rejected");
			disconnected.resolve();
		});
		
		//Connect
		let errorCode = connection.connect("127.0.0.1", 1936, "test");
		test.equal(errorCode, RTMPServer.NetConnectionErrorCode.NoError, "Expect initial TCP connection to be successful");
		
		await disconnected;
		
		//Stop server
		rtmp.stop();
		
		test.end();
	});

	suite.end();

}).then(() =>
{
	RTMPServer.terminate();
});

