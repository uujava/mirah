package org.mirah.util

import java.lang.reflect.Modifier

class Test
  macro def assertEquals(expected:Node, block:Block):Node
    body = block.body
    var = gensym
    src = SimpleString.new body.position.source.substring(body.position.startChar, body.position.endChar)
    source = gensym
    value = quote do
       `var` = `body`
       `source` = `src`.trim
       if `expected` != `var`
         raise org::mirah::util::AssertionError.new `expected`, `var`, `source`
       end
    end
    value
  end

  macro def assertTrue(block:Block):Node
    body = block.body
    var = gensym
    src = SimpleString.new body.position.source.substring(body.position.startChar, body.position.endChar)
    value = quote do
       `var` = `body`
       if `var` != true
         raise org::mirah::util::AssertionError.new true, `var`, `src`.trim
       end
    end
    value
  end

  def self.main(*args:String):void
    # todo setup/teardown
    setup = nil
    tear_down = nil
    totalFailed = 0

    args.each do |class_name|
      errors = []
      ok = 0
      failed = 0
      clazz = Class.forName class_name

      methods = clazz.getDeclaredMethods
      puts "test suite: #{clazz}"
      methods.each do |method|
        test = clazz.newInstance
        name = method.getName
        flag = method.getModifiers
        if name.startsWith 'test' and Modifier.isPublic(flag) and !Modifier.isStatic(flag)
          begin
            method.invoke test
            ok+=1
            print "."
          rescue AssertionError => ax
            failed +=1
            ax.method = name
            ax.clazz = clazz
            errors.add ax
            print "F"
          rescue Throwable => ex
            failed +=1
            ax = AssertionError.new ex, ""
            ax.method = name
            ax.clazz = clazz
            errors.add ax
            print "F"
          end
        end
      end
      errors.each do |err:AssertionError|
        puts err.message
      end
      puts "\nfinished #{clazz} #{ok + failed} OK: #{ok} Failed: #{failed}"
      totalFailed += failed
    end
    System.exit totalFailed
  end

end

class AssertionError < RuntimeException
 attr_reader expected:Object,
             actual:Object,
             src: String

 attr_accessor clazz:Class, method:String

 def initialize(expected:Object, actual:Object, src: String)
   @expected = expected
   @actual = actual
   @src = src
 end

 def initialize(ex:Throwable,src: String):void
   @src = src
   @ex = ex
 end

 def message:String
   if @ex
     return "Test: #{clazz} method: #{method}\nFailure:#{@ex.getMessage}\nSource:#{@src}"
   else
     return "Test: #{clazz} method: #{method}\nexpected:#{@expected}\nactual#{@actual}\nSource:#{@src}"
   end
 end
end