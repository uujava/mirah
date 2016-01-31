package org.mirah.typer.closures

import mirah.lang.ast.*
import org.mirah.typer.BetterClosureBuilder

class BlockCloneListener implements CloneListener
   def initialize(closure_builder:BetterClosureBuilder)
     @closure_builder = closure_builder
   end
   def wasCloned(interim:Node, new:Node)
     old = @closure_builder.blockCloneMapNewOld.get(interim)
     @closure_builder.blockCloneMapNewOld.put(new,old)
     @closure_builder.blockCloneMapOldNew.put(old,new)
     new.whenCloned self
   end
end