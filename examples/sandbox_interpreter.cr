require "../src/context"

enum OpCode
  Add
  Pause
  Spin
end

record Instruction, op : OpCode, amount : Int32

class MiniInterpreter
  getter accumulator

  def initialize(@program : Array(Instruction))
    @accumulator = 0
  end

  def run(ctx : Context) : Int32
    @program.each do |instruction|
      ctx.checkpoint!
      execute(ctx, instruction)
    end

    @accumulator
  end

  private def execute(ctx : Context, instruction : Instruction) : Nil
    case instruction.op
    in .add?
      @accumulator += instruction.amount
    in .pause?
      Context.sleep(ctx, instruction.amount.milliseconds)
    in .spin?
      instruction.amount.times do
        ctx.checkpoint!
        @accumulator += 1
      end
    end
  end
end

program = [
  Instruction.new(OpCode::Add, 10),
  Instruction.new(OpCode::Spin, 100),
  Instruction.new(OpCode::Pause, 100),
  Instruction.new(OpCode::Add, 1),
]

ctx = Context.with_timeout(20.milliseconds)
interpreter = MiniInterpreter.new(program)

begin
  puts "completed: #{interpreter.run(ctx)}"
rescue ex : Context::Cancelled
  puts "sandbox stopped: #{ex.message}; accumulator=#{interpreter.accumulator}"
end
