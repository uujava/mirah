package org.mirah.util

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
         raise "test failed #{`source`}\n #{`expected`} <=> #{`var`}"
       else
         puts "test passed: #{`source`}\n => #{`expected`}"
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
      ok = 0
      failed = 0
      clazz = Class.forName class_name
      test = clazz.newInstance
      methods = clazz.getDeclaredMethods
      System.out.println "test suite: #{clazz}"
      methods.each do |method|
        name = method.getName
        if name.startsWith 'test'
          begin
            method.invoke test
            ok+=1
            System.out.print "."
          rescue Throwable => ex
            failed +=1
            System.out.print "F"
          end
        end
      end
      System.out.println "\nfinished #{clazz} #{ok + failed} OK: #{ok} Failed: #{failed}"
      totalFailed += failed
    end
    System.exit totalFailed
  end

end