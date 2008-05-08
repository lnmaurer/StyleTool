require 'tk'

class Document
  attr_reader :name, :wordCount, :countedWords
  def initialize(name,text)
    @name = name
    @countedWords = Hash.new(0)
    words = text.downcase.scan(/\w+/)
    if block_given?
      words.each{|word| @countedWords[word] += 1 if yield(word)}
    else
      words.each{|word| @countedWords[word] += 1}
    end
    @wordCount = words.size
  end
  def words
    @countedWords.keys
  end
  def count(word)
    #will return 0 if 'word' not in 'countedWords' since 0 is the default value
    @countedWords[word]
  end
  def relativeFrequency(word)
    @countedWords[word] / @wordCount.to_f
  end
end

class Interface
  def initialize
    @documents = Array.new
    @masterWordList = Array.new

    #and now for the GUI
    @root = TkRoot.new() {title 'Style Tool'}

    TkLabel.new{
      @root
      text "Loaded files:"
    }.grid('column'=>0,'row'=>0, 'sticky'=>'w')
    @listbox = TkListbox.new(@root) {
      selectmode "none"
      height 5
    }.grid('column'=>1, 'row'=>0,'sticky'=>'w', 'padx'=>5, 'pady'=>5)


    addfile = proc {
      filename = Tk.getOpenFile
      #if the user clicks "cancel" in the dialog box then filename == ""
      self.addFile(filename) unless filename == ""
    }
    addfolder = proc {
      foldername = Tk.chooseDirectory
      self.addFolder(foldername) unless foldername == ""
    }
    save = proc {
      filename = Tk.getSaveFile("filetypes"=>[["CSV", ".csv"]])
      self.saveToCSV(filename) unless filename == ""
    }
    TkButton.new(@root) {
      text    'Add file'
      command addfile
    }.grid('column'=>0, 'row'=>1,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Add folder'
      command addfolder
    }.grid('column'=>1, 'row'=>1,'sticky'=>'w', 'padx'=>5, 'pady'=>5)
    TkButton.new(@root) {
      text    'Save as CSV'
      command save
    }.grid('column'=>2, 'row'=>1,'sticky'=>'w', 'padx'=>5, 'pady'=>5)

    wordlisttoggled = proc {
      @documents = Array.new
      @masterWordList = Array.new
      @listbox.delete(0) while @listbox.size != 0
      if @wordListSpecified.get_value == "1"
        @masterWordList = IO.read(Tk.getOpenFile).downcase.scan(/\w+/).uniq
      end
    }
    @wordListSpecified = TkCheckButton.new(@root){
      text "Count specific words only"
      command wordlisttoggled
    }.grid('column'=>0,'row'=> 2, 'sticky'=>'w')

  end
  def addFile(filename)
    @listbox.insert('end', filename)
    if @wordListSpecified
      newdoc = Document.new(filename,IO.read(filename)) {|word| @masterWordList.include?(word)}
    else
      newdoc = Document.new(filename,IO.read(filename))
      @masterWordList = (@masterWordList | newdoc.words).sort
    end
    @documents.push(newdoc)
  end
  def addFolder(path)
    Dir.chdir(path){Dir.foreach(path){|file| self.addFile(file) if File.file?(file)}}
  end
  def saveToCSV(filename)
    File.open(filename, "w") do |file|
      #prints the file name at the top of each column
      @documents.each{|doc| file.print(",",doc.name)}
      file.print("\n")
      @masterWordList.each do |word|
        file.print(word)
        @documents.each{|doc| file.print(",",doc.relativeFrequency(word))}
        file.print("\n")
      end
    end
  end
end


if __FILE__ == $0
  Interface.new
  Tk.mainloop()
end