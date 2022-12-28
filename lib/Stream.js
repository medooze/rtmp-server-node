const Emitter			= require("./Emitter");
const Status			= require("./Status");
const IncomingStamBridge	= require("./IncomingStreamBridge")


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
			//Launch async so we can set listeners safely
			setTimeout(()=>{
				try 
				{
					//If not ended already
					if (this.emitter)
						//Emit event
						this.emitter.emit("cmd",{
							name	: name,
							params	: params
						},...extra);
				} catch(e){
					//Ignore
				}
			},0);
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
		return new IncomingStamBridge(this.stream);
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
		
		//Stop stream
		this.stream.Stop();
		
		//Stop emitter
		super.stop();
		
		//Stop listener
		this.stream = null;
	}
}

module.exports = Stream;
