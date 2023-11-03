const Native			= require("./Native.js");
const Server			= require("./Server.js");
const Application		= require("./Application.js");
const IncomingStreamBridge	= require("./IncomingStreamBridge");

/** @typedef {import("./Status").Status} Status */

/** @namespace */
const RTMPServer = {};
RTMPServer.NetStream = require("./Status.js").NetStream;
RTMPServer.NetConnection = require("./Status.js").NetConnection;

//INitialize Stuff
Native.RTMPServerModule.Initialize();

/**
 * Close async handlers so nodejs can exit nicely
 * Only call it once!
 * @memberof RTMPServer
  */
RTMPServer.terminate = function()
{
	//Set flag
	Native.RTMPServerModule.Terminate();
};


/**
 * Enable or disable log level traces
 * @memberof RTMPServer
 * @param {Boolean} flag
 */
RTMPServer.enableLog= function(flag)
{
	//Set flag
	Native.RTMPServerModule.EnableLog(flag);
};


/**
 * Enable or disable debug level traces
 * @memberof RTMPServer
 * @param {Boolean} flag
 */
RTMPServer.enableDebug = function(flag)
{
	//Set flag
	Native.RTMPServerModule.EnableDebug(flag);
};

/**
 * Enable or disable ultra debug level traces
 * @memberof RTMPServer
 * @param {Boolean} flag
 */
RTMPServer.enableUltraDebug = function(/** @type {boolean} */ flag)
{
	//Set flag
	Native.RTMPServerModule.EnableUltraDebug(flag);
};

/**
 * Create a new server
 * @memberof RTMPServer
 * @returns {Server} The new created server
 */
RTMPServer.createServer = function()
{
	//Cretate new rtmp server endpoint
	return new Server();
};



/**
 * Create a new incoming stream bridge to RTP
 * @memberof RTMPServer
 * @returns {IncomingStreamBridge} The new created server
 */
RTMPServer.createIncomingStreamBridge = function(
		/** @type {number | undefined} */ maxLateOffset = undefined,
		/** @type {number | undefined} */ maxBufferingTime = undefined)
	{
		if (maxLateOffset === undefined) maxLateOffset = 200;
		if (maxBufferingTime === undefined) maxBufferingTime = 600;

		if (maxLateOffset<0)
			throw Error("maxLateOffset can't be negative");
		if (maxBufferingTime<0)
			throw Error("maxBufferingTime can't be negative");
		if (maxLateOffset>1000)
			throw Error("maxLateOffset can't be higher than 1000");
		if (maxBufferingTime>1000)
			throw Error("maxBufferingTime can't be higher than 1000");
		//Create new rtp stream bridge
		return new IncomingStreamBridge(maxLateOffset, maxBufferingTime);
};

/**
 * Create a new application
 * @memberof RTMPServer
 * @returns {Application} The new created application
 */
RTMPServer.createApplication = function()
{
	//Cretate new rtp endpoint
	return new Application();
};

module.exports = RTMPServer;
