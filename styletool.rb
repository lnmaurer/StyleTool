

class Document
  attr_reader :name, :wordCount, :countedWords
  def initialize(name,text)
    @name = name
    @countedWords = Hash.new(0)
    words = text.downcase.scan(/\w+/)
    words.each{|word| @countedWords[word] += 1}
    @wordCount = words.size
  end
  def words
    @countedWords.keys
  end
  def count(word)
    #will return 0 if 'word' not in 'countedWords' since 0 is the default value
    @countedWords[word]
  end
  def wordScore(word)
    @countedWords[word] / @wordCount.to_f
  end
end

class Interface
private
  def updateMasterWordList
    @masterWordList = @documents.inject{|list,doc| doc.words | list}
  end
public
  def initialize
    @documents = Array.new
    @masterWordList = Array.new
  end
  def addFile(filename)
    newdoc = Document.new(filename,IO.read(filename))
    @documents.push(newdoc)
    @masterWordList = (@masterWordList | newdoc.words).sort
  end
  def addFolder(path)
    Dir.chdir(path){Dir.foreach(path){|file| self.addFile(file) if File.file?(file)}}
  end
  def saveToCSV(filename)
    File.open(filename, "w") do |file|
      @documents.each{|doc| file.print(",",doc.name)}
      file.print("\n")
      @masterWordList.each do |word|
        file.print(word)
        @documents.each{|doc| file.print(",",doc.wordScore(word))}
        file.print("\n")
      end
    end
  end
end