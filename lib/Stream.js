const Emitter			= require("./Emitter");
const Status			= require("./Status");


class Stream extends Emitter
{
	constructor(stream)
	{
		//Intit emitted
		super();
		
		//Store props
		this.id = 0; //stream.GetId();
		this.stream = stream;
		
		//On command listener
		this.oncmd = (name,params,...extra) => {
			//Emit event
			this.emitter.emit("cmd",{
				name	: name,
				params	: params
			},...extra);
		};
		//On stopp event (deleteStream net command)
		this.onstopped = ()=>{
			//Stop us
			this.stop();
		};
		
		//Add us as listener
		this.stream.SetListener(this);
	}
	
	getId()
	{
		return this.id;
	}
	
	sendStatus(status,desc)
	{
		//Send it
		this.stream.SendStatus(status.code,status.level,desc || status.code);
	}
	
	createIncomingStreamBridge()
	{
		return new IncomingStreamBridge(this.stream);
	}
	
	stop()
	{
		//Check not already stopped
		if (!this.stream)
			//Done
			return;
		
		//Remove us as listener
		this.stream.ResetListener();
		
		/**
		* IncomingStream stopped event
		*
		* @name stopped
		* @memberof IncomingStream
		* @kind event
		* @argument {IncomingStream} incomingStream
		*/
		this.emitter.emit("stopped", this);
		
		//Stop emitter
		super.stop();
		
		//Stop listener
		this.stream = null;
	}
}

module.exports = Stream;
