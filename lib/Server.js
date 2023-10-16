const Native			= require("./Native.js");

/** @typedef {import("./Application")} Application */

class Server
{
	constructor()
	{
		//Create native server
		this.server = new Native.RTMPServerFacade(this);
	}
	
	start(/** @type {number} */ port)
	{
		//Create native server
		this.server.Start(port);
	}
	
	addApplication(
		/** @type {string} */ name,
		/** @type {Application} */ app)
	{
		//Add to server
		this.server.AddApplication(name,app.application);
	}
	
	stop()
	{
		//Stop server
		this.server.Stop();
		
		//Release mem
		//@ts-expect-error
		this.server = null;
	}
}

module.exports = Server;
