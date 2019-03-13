const Native			= require("./Native.js");

class Server
{
	constructor()
	{
		//Create native server
		this.server = new Native.RTMPServerFacade(this);
	}
	
	start(port)
	{
		//Create native server
		this.server.Start(port);
	}
	
	addApplication(name,app)
	{
		//Add to server
		this.server.AddApplication(name,app.application);
	}
	
	stop()
	{
		//Stop server
		this.server.Stop();
		
		//Release mem
		this.server = null;
	}
}

module.exports = Server;
