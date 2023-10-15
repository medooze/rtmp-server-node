const Native		= require("./Native.js");
const Client		= require("./Client.js");
const Emitter		= require("medooze-event-emitter");
const SharedPointer	= require("./SharedPointer.js")

class Application extends Emitter
{
	constructor()
	{
		//instantiate mitter
		super();
		
		//Create native server
		this.application = new Native.RTMPApplicationImpl(this);
		
		//Client map
		this.clients = new Map();
		
		//The event handler
		this.onconnect = (peerIp,peerPort,appName,conn) =>{
			//Create new connection
			const client = new Client(SharedPointer(conn),peerIp,peerPort,appName);
			//Add to client list
			this.clients.set(client.getId(),client);
			//event handlers
			client.once("stopped",(client)=>{
				//Remove client from map
				this.clients.delete(client.getId());
			});
			//Emit event
			this.emit("connect",client);
		};
	}
	
	
	stop()
	{
		//Stop clients
		for (const [clientId,client] of this.clients)
			//Stop it
			client.stop();
		
		//Emit stopped
		this.emit("stopped",this);
		
		//Close emitter
		super.stop();
		
	}
}

module.exports = Application;
