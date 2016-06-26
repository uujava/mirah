class AnnotationsTest < Test::Unit::TestCase

  def deprecated
    @deprecated ||= java.lang.Deprecated.java_class
  end

  def test_annotation_on_a_method
    cls, = compile(<<-EOF)
      $Deprecated
      def foo
        'foo'
      end
    EOF

    assert_not_nil cls.java_class.java_method('foo').annotation(deprecated)
    assert_nil cls.java_class.annotation(deprecated)
  end

  def test_annotation_on_a_argument
    cls, = compile(<<-EOF)
      def foo($Deprecated x:int, $Deprecated y:String='', $Deprecated *z:Integer)
        'foo'
      end
    EOF

    assert_nil cls.java_class.annotation(deprecated)
    java_method = cls.java_class.declared_class_methods[0]
    assert_nil java_method.annotation(deprecated)
    assert_not_nil java_method.parameter_annotations[0][0]
    assert_not_nil java_method.parameter_annotations[1][0]
    assert_not_nil java_method.parameter_annotations[2][0]
  end

  def test_annotation_on_a_argumenttest_from_constant
    return
    cls, = compile(<<-EOF)
      import org.foo.IntAnno
      class IntValAnnotation
        Value = 1
        def bar($IntAnno[name: "bar", value: Value] x:int):void
        end
      end
      method = IntValAnnotation.class.getDeclaredMethods[0]
      anno = method.getAnnotation(IntAnno.class)
      puts anno.value
    EOF

    assert_run_output("1\n", cls)
  end

  def test_annotation_on_a_class
    cls, = compile(<<-EOF)
      $Deprecated
      class Annotated
      end
    EOF
    assert_not_nil cls.java_class.annotation(deprecated)
  end

  def test_annotation_on_a_field
    cls, = compile(<<-EOF)
      class AnnotatedField
        def initialize
          $Deprecated
          @foo = 1
        end
      end
    EOF

    assert_not_nil cls.java_class.declared_fields[0].annotation(deprecated)
  end

  def test_annotation_with_an_integer
    cls, = compile(<<-EOF)
      import org.foo.IntAnno
      class IntValAnnotation
        $IntAnno[name: "bar", value: 1]
        def bar
        end
      end
      method = IntValAnnotation.class.getMethod("bar")
      anno = method.getAnnotation(IntAnno.class)
      puts anno.value
    EOF

    assert_run_output("1\n", cls)
  end

  def test_annotation_from_constant
    return
    cls, = compile(<<-EOF)
      import org.foo.IntAnno
      class IntValAnnotation
        Value = 1
        $IntAnno[name: "bar", value: Value]
        def bar
        end
      end
      method = IntValAnnotation.class.getMethod("bar")
      anno = method.getAnnotation(IntAnno.class)
      puts anno.value
    EOF

    assert_run_output("1\n", cls)
  end

end
